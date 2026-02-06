/*
 * Astra Module: Process
 * Managed subprocess execution with pipes (no shell).
 */

#include <astra.h>

#ifndef _WIN32
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#define PROCESS_MT "process.handle"

typedef struct
{
    pid_t pid;
    int stdout_fd;
    int stderr_fd;
    int exited;
    int exit_code;
    int term_signal;
} process_handle_t;

static process_handle_t *check_proc(lua_State *L)
{
    return (process_handle_t *)luaL_checkudata(L, 1, PROCESS_MT);
}

static void close_fd(int *fd)
{
    if(fd && *fd >= 0)
    {
        close(*fd);
        *fd = -1;
    }
}

static void set_nonblock(int fd)
{
    int flags = fcntl(fd, F_GETFL, 0);
    if(flags >= 0)
    {
        fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    }
}

static int read_fd_to_lua(lua_State *L, int *fd)
{
    if(!fd || *fd < 0)
    {
        lua_pushnil(L);
        return 1;
    }

    char buf[4096];
    size_t total = 0;
    luaL_Buffer lb;
    luaL_buffinit(L, &lb);

    for(;;)
    {
        const ssize_t r = read(*fd, buf, sizeof(buf));
        if(r > 0)
        {
            luaL_addlstring(&lb, buf, (size_t)r);
            total += (size_t)r;
            continue;
        }
        if(r == 0)
        {
            close_fd(fd);
            break;
        }
        if(errno == EAGAIN || errno == EWOULDBLOCK)
        {
            break;
        }
        close_fd(fd);
        break;
    }

    if(total == 0)
    {
        lua_pushnil(L);
        return 1;
    }

    luaL_pushresult(&lb);
    return 1;
}

static int proc_read_stdout(lua_State *L)
{
    process_handle_t *proc = check_proc(L);
    return read_fd_to_lua(L, &proc->stdout_fd);
}

static int proc_read_stderr(lua_State *L)
{
    process_handle_t *proc = check_proc(L);
    return read_fd_to_lua(L, &proc->stderr_fd);
}

static int proc_poll(lua_State *L)
{
    process_handle_t *proc = check_proc(L);
    if(proc->pid <= 0)
    {
        lua_pushnil(L);
        return 1;
    }

    if(proc->exited)
    {
        lua_newtable(L);
        lua_pushinteger(L, proc->exit_code);
        lua_setfield(L, -2, "exit_code");
        lua_pushinteger(L, proc->term_signal);
        lua_setfield(L, -2, "signal");
        return 1;
    }

    int status = 0;
    const pid_t ret = waitpid(proc->pid, &status, WNOHANG);
    if(ret == 0)
    {
        lua_pushnil(L);
        return 1;
    }
    if(ret < 0)
    {
        lua_pushnil(L);
        return 1;
    }

    proc->exited = 1;
    proc->exit_code = 0;
    proc->term_signal = 0;

    if(WIFEXITED(status))
        proc->exit_code = WEXITSTATUS(status);
    if(WIFSIGNALED(status))
        proc->term_signal = WTERMSIG(status);

    lua_newtable(L);
    lua_pushinteger(L, proc->exit_code);
    lua_setfield(L, -2, "exit_code");
    lua_pushinteger(L, proc->term_signal);
    lua_setfield(L, -2, "signal");
    return 1;
}

static int proc_pid(lua_State *L)
{
    process_handle_t *proc = check_proc(L);
    lua_pushinteger(L, proc->pid);
    return 1;
}

static int proc_signal(lua_State *L, int signum)
{
    process_handle_t *proc = check_proc(L);
    if(proc->pid <= 0)
    {
        lua_pushboolean(L, 0);
        return 1;
    }
    const int rc = kill(proc->pid, signum);
    lua_pushboolean(L, rc == 0);
    return 1;
}

static int proc_terminate(lua_State *L)
{
    const int signum = luaL_optinteger(L, 2, SIGTERM);
    return proc_signal(L, signum);
}

static int proc_kill(lua_State *L)
{
    return proc_signal(L, SIGKILL);
}

static int proc_close(lua_State *L)
{
    process_handle_t *proc = check_proc(L);
    close_fd(&proc->stdout_fd);
    close_fd(&proc->stderr_fd);
    lua_pushboolean(L, 1);
    return 1;
}

static int proc_gc(lua_State *L)
{
    process_handle_t *proc = check_proc(L);
    close_fd(&proc->stdout_fd);
    close_fd(&proc->stderr_fd);
    return 0;
}

static char **collect_argv(lua_State *L, int idx, int *argc_out)
{
    const int argc = (int)luaL_len(L, idx);
    if(argc <= 0)
        return NULL;

    char **argv = (char **)calloc((size_t)argc + 1, sizeof(char *));
    if(!argv)
        return NULL;

    for(int i = 1; i <= argc; i++)
    {
        lua_rawgeti(L, idx, i);
        const char *arg = lua_tostring(L, -1);
        if(!arg)
        {
            lua_pop(L, 1);
            for(int j = 0; j < i - 1; j++)
                free(argv[j]);
            free(argv);
            return NULL;
        }
        argv[i - 1] = strdup(arg);
        lua_pop(L, 1);
    }
    argv[argc] = NULL;
    if(argc_out)
        *argc_out = argc;
    return argv;
}

static void free_argv(char **argv)
{
    if(!argv)
        return;
    for(int i = 0; argv[i]; i++)
        free(argv[i]);
    free(argv);
}

static int proc_spawn(lua_State *L)
{
    luaL_checktype(L, 1, LUA_TTABLE);

    int argc = 0;
    char **argv = collect_argv(L, 1, &argc);
    if(!argv || argc == 0)
    {
        free_argv(argv);
        return luaL_error(L, "argv must be a non-empty table");
    }

    int pipe_stdout = 0;
    int pipe_stderr = 0;
    const char *cwd = NULL;

    if(lua_istable(L, 2))
    {
        lua_getfield(L, 2, "stdout");
        if(lua_isstring(L, -1))
        {
            const char *v = lua_tostring(L, -1);
            if(v && strcmp(v, "pipe") == 0)
                pipe_stdout = 1;
        }
        else if(lua_isboolean(L, -1) && lua_toboolean(L, -1))
            pipe_stdout = 1;
        lua_pop(L, 1);

        lua_getfield(L, 2, "stderr");
        if(lua_isstring(L, -1))
        {
            const char *v = lua_tostring(L, -1);
            if(v && strcmp(v, "pipe") == 0)
                pipe_stderr = 1;
        }
        else if(lua_isboolean(L, -1) && lua_toboolean(L, -1))
            pipe_stderr = 1;
        lua_pop(L, 1);

        lua_getfield(L, 2, "cwd");
        if(lua_isstring(L, -1))
            cwd = lua_tostring(L, -1);
        lua_pop(L, 1);
    }

    int stdout_pipe[2] = { -1, -1 };
    int stderr_pipe[2] = { -1, -1 };
    if(pipe_stdout && pipe(stdout_pipe) != 0)
    {
        free_argv(argv);
        return luaL_error(L, "failed to create stdout pipe");
    }
    if(pipe_stderr && pipe(stderr_pipe) != 0)
    {
        if(pipe_stdout)
        {
            close(stdout_pipe[0]);
            close(stdout_pipe[1]);
        }
        free_argv(argv);
        return luaL_error(L, "failed to create stderr pipe");
    }

    const pid_t pid = fork();
    if(pid < 0)
    {
        if(pipe_stdout)
        {
            close(stdout_pipe[0]);
            close(stdout_pipe[1]);
        }
        if(pipe_stderr)
        {
            close(stderr_pipe[0]);
            close(stderr_pipe[1]);
        }
        free_argv(argv);
        return luaL_error(L, "fork failed");
    }

    if(pid == 0)
    {
        if(pipe_stdout)
        {
            close(stdout_pipe[0]);
            dup2(stdout_pipe[1], STDOUT_FILENO);
            close(stdout_pipe[1]);
        }
        if(pipe_stderr)
        {
            close(stderr_pipe[0]);
            dup2(stderr_pipe[1], STDERR_FILENO);
            close(stderr_pipe[1]);
        }
        if(cwd && chdir(cwd) != 0)
        {
            _exit(127);
        }

        /*
         * Do not leak Astra's open file descriptors (server sockets, db files, etc)
         * into subprocesses. This also prevents orphaned children from keeping the
         * HTTP port busy after parent exit/crash.
         */
        long max_fd = sysconf(_SC_OPEN_MAX);
        if(max_fd < 0)
            max_fd = 1024;
        for(int fd = 3; fd < max_fd; fd++)
            close(fd);

        execvp(argv[0], argv);
        _exit(127);
    }

    if(pipe_stdout)
    {
        close(stdout_pipe[1]);
        set_nonblock(stdout_pipe[0]);
    }
    if(pipe_stderr)
    {
        close(stderr_pipe[1]);
        set_nonblock(stderr_pipe[0]);
    }

    process_handle_t *proc = (process_handle_t *)lua_newuserdata(L, sizeof(process_handle_t));
    memset(proc, 0, sizeof(*proc));
    proc->pid = pid;
    proc->stdout_fd = pipe_stdout ? stdout_pipe[0] : -1;
    proc->stderr_fd = pipe_stderr ? stderr_pipe[0] : -1;
    proc->exited = 0;
    proc->exit_code = 0;
    proc->term_signal = 0;

    luaL_getmetatable(L, PROCESS_MT);
    lua_setmetatable(L, -2);

    free_argv(argv);
    return 1;
}

LUA_API int luaopen_process(lua_State *L)
{
    static const luaL_Reg api[] =
    {
        { "spawn", proc_spawn },
        { NULL, NULL }
    };

    static const luaL_Reg meta[] =
    {
        { "read_stdout", proc_read_stdout },
        { "read_stderr", proc_read_stderr },
        { "poll", proc_poll },
        { "pid", proc_pid },
        { "terminate", proc_terminate },
        { "kill", proc_kill },
        { "close", proc_close },
        { "__gc", proc_gc },
        { NULL, NULL }
    };

    luaL_newmetatable(L, PROCESS_MT);
    luaL_setfuncs(L, meta, 0);
    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);

    luaL_newlib(L, api);
    lua_setglobal(L, "process");
    return 0;
}

#else
LUA_API int luaopen_process(lua_State *L)
{
    lua_newtable(L);
    lua_setglobal(L, "process");
    return 0;
}
#endif
