# 1 "lib/http.c"
# 1 "<command-line>"
# 1 "lib/http.c"
# 1 "lib/http.h" 1



# 1 "/opt/rh/devtoolset-2/root/usr/lib/gcc/x86_64-redhat-linux/4.8.2/include/stdint.h" 1 3 4
# 9 "/opt/rh/devtoolset-2/root/usr/lib/gcc/x86_64-redhat-linux/4.8.2/include/stdint.h" 3 4
# 1 "/usr/include/stdint.h" 1 3 4
# 26 "/usr/include/stdint.h" 3 4
# 1 "/usr/include/features.h" 1 3 4
# 361 "/usr/include/features.h" 3 4
# 1 "/usr/include/sys/cdefs.h" 1 3 4
# 373 "/usr/include/sys/cdefs.h" 3 4
# 1 "/usr/include/bits/wordsize.h" 1 3 4
# 374 "/usr/include/sys/cdefs.h" 2 3 4
# 362 "/usr/include/features.h" 2 3 4
# 385 "/usr/include/features.h" 3 4
# 1 "/usr/include/gnu/stubs.h" 1 3 4



# 1 "/usr/include/bits/wordsize.h" 1 3 4
# 5 "/usr/include/gnu/stubs.h" 2 3 4




# 1 "/usr/include/gnu/stubs-64.h" 1 3 4
# 10 "/usr/include/gnu/stubs.h" 2 3 4
# 386 "/usr/include/features.h" 2 3 4
# 27 "/usr/include/stdint.h" 2 3 4
# 1 "/usr/include/bits/wchar.h" 1 3 4
# 28 "/usr/include/stdint.h" 2 3 4
# 1 "/usr/include/bits/wordsize.h" 1 3 4
# 29 "/usr/include/stdint.h" 2 3 4
# 37 "/usr/include/stdint.h" 3 4
typedef signed char int8_t;
typedef short int int16_t;
typedef int int32_t;

typedef long int int64_t;







typedef unsigned char uint8_t;
typedef unsigned short int uint16_t;

typedef unsigned int uint32_t;



typedef unsigned long int uint64_t;
# 66 "/usr/include/stdint.h" 3 4
typedef signed char int_least8_t;
typedef short int int_least16_t;
typedef int int_least32_t;

typedef long int int_least64_t;






typedef unsigned char uint_least8_t;
typedef unsigned short int uint_least16_t;
typedef unsigned int uint_least32_t;

typedef unsigned long int uint_least64_t;
# 91 "/usr/include/stdint.h" 3 4
typedef signed char int_fast8_t;

typedef long int int_fast16_t;
typedef long int int_fast32_t;
typedef long int int_fast64_t;
# 104 "/usr/include/stdint.h" 3 4
typedef unsigned char uint_fast8_t;

typedef unsigned long int uint_fast16_t;
typedef unsigned long int uint_fast32_t;
typedef unsigned long int uint_fast64_t;
# 120 "/usr/include/stdint.h" 3 4
typedef long int intptr_t;


typedef unsigned long int uintptr_t;
# 135 "/usr/include/stdint.h" 3 4
typedef long int intmax_t;
typedef unsigned long int uintmax_t;
# 10 "/opt/rh/devtoolset-2/root/usr/lib/gcc/x86_64-redhat-linux/4.8.2/include/stdint.h" 2 3 4
# 5 "lib/http.h" 2
# 1 "/opt/rh/devtoolset-2/root/usr/lib/gcc/x86_64-redhat-linux/4.8.2/include/stdbool.h" 1 3 4
# 6 "lib/http.h" 2
# 1 "/usr/include/netinet/in.h" 1 3 4
# 25 "/usr/include/netinet/in.h" 3 4
# 1 "/usr/include/sys/socket.h" 1 3 4
# 26 "/usr/include/sys/socket.h" 3 4


# 1 "/usr/include/sys/uio.h" 1 3 4
# 24 "/usr/include/sys/uio.h" 3 4
# 1 "/usr/include/sys/types.h" 1 3 4
# 28 "/usr/include/sys/types.h" 3 4


# 1 "/usr/include/bits/types.h" 1 3 4
# 28 "/usr/include/bits/types.h" 3 4
# 1 "/usr/include/bits/wordsize.h" 1 3 4
# 29 "/usr/include/bits/types.h" 2 3 4


typedef unsigned char __u_char;
typedef unsigned short int __u_short;
typedef unsigned int __u_int;
typedef unsigned long int __u_long;


typedef signed char __int8_t;
typedef unsigned char __uint8_t;
typedef signed short int __int16_t;
typedef unsigned short int __uint16_t;
typedef signed int __int32_t;
typedef unsigned int __uint32_t;

typedef signed long int __int64_t;
typedef unsigned long int __uint64_t;







typedef long int __quad_t;
typedef unsigned long int __u_quad_t;
# 131 "/usr/include/bits/types.h" 3 4
# 1 "/usr/include/bits/typesizes.h" 1 3 4
# 132 "/usr/include/bits/types.h" 2 3 4


typedef unsigned long int __dev_t;
typedef unsigned int __uid_t;
typedef unsigned int __gid_t;
typedef unsigned long int __ino_t;
typedef unsigned long int __ino64_t;
typedef unsigned int __mode_t;
typedef unsigned long int __nlink_t;
typedef long int __off_t;
typedef long int __off64_t;
typedef int __pid_t;
typedef struct { int __val[2]; } __fsid_t;
typedef long int __clock_t;
typedef unsigned long int __rlim_t;
typedef unsigned long int __rlim64_t;
typedef unsigned int __id_t;
typedef long int __time_t;
typedef unsigned int __useconds_t;
typedef long int __suseconds_t;

typedef int __daddr_t;
typedef long int __swblk_t;
typedef int __key_t;


typedef int __clockid_t;


typedef void * __timer_t;


typedef long int __blksize_t;




typedef long int __blkcnt_t;
typedef long int __blkcnt64_t;


typedef unsigned long int __fsblkcnt_t;
typedef unsigned long int __fsblkcnt64_t;


typedef unsigned long int __fsfilcnt_t;
typedef unsigned long int __fsfilcnt64_t;

typedef long int __ssize_t;



typedef __off64_t __loff_t;
typedef __quad_t *__qaddr_t;
typedef char *__caddr_t;


typedef long int __intptr_t;


typedef unsigned int __socklen_t;
# 31 "/usr/include/sys/types.h" 2 3 4



typedef __u_char u_char;
typedef __u_short u_short;
typedef __u_int u_int;
typedef __u_long u_long;
typedef __quad_t quad_t;
typedef __u_quad_t u_quad_t;
typedef __fsid_t fsid_t;




typedef __loff_t loff_t;



typedef __ino_t ino_t;
# 61 "/usr/include/sys/types.h" 3 4
typedef __dev_t dev_t;




typedef __gid_t gid_t;




typedef __mode_t mode_t;




typedef __nlink_t nlink_t;




typedef __uid_t uid_t;





typedef __off_t off_t;
# 99 "/usr/include/sys/types.h" 3 4
typedef __pid_t pid_t;





typedef __id_t id_t;




typedef __ssize_t ssize_t;





typedef __daddr_t daddr_t;
typedef __caddr_t caddr_t;





typedef __key_t key_t;
# 133 "/usr/include/sys/types.h" 3 4
# 1 "/usr/include/time.h" 1 3 4
# 58 "/usr/include/time.h" 3 4


typedef __clock_t clock_t;



# 74 "/usr/include/time.h" 3 4


typedef __time_t time_t;



# 92 "/usr/include/time.h" 3 4
typedef __clockid_t clockid_t;
# 104 "/usr/include/time.h" 3 4
typedef __timer_t timer_t;
# 134 "/usr/include/sys/types.h" 2 3 4
# 147 "/usr/include/sys/types.h" 3 4
# 1 "/opt/rh/devtoolset-2/root/usr/lib/gcc/x86_64-redhat-linux/4.8.2/include/stddef.h" 1 3 4
# 212 "/opt/rh/devtoolset-2/root/usr/lib/gcc/x86_64-redhat-linux/4.8.2/include/stddef.h" 3 4
typedef long unsigned int size_t;
# 148 "/usr/include/sys/types.h" 2 3 4



typedef unsigned long int ulong;
typedef unsigned short int ushort;
typedef unsigned int uint;
# 201 "/usr/include/sys/types.h" 3 4
typedef unsigned int u_int8_t __attribute__ ((__mode__ (__QI__)));
typedef unsigned int u_int16_t __attribute__ ((__mode__ (__HI__)));
typedef unsigned int u_int32_t __attribute__ ((__mode__ (__SI__)));
typedef unsigned int u_int64_t __attribute__ ((__mode__ (__DI__)));

typedef int register_t __attribute__ ((__mode__ (__word__)));
# 217 "/usr/include/sys/types.h" 3 4
# 1 "/usr/include/endian.h" 1 3 4
# 37 "/usr/include/endian.h" 3 4
# 1 "/usr/include/bits/endian.h" 1 3 4
# 38 "/usr/include/endian.h" 2 3 4
# 61 "/usr/include/endian.h" 3 4
# 1 "/usr/include/bits/byteswap.h" 1 3 4
# 28 "/usr/include/bits/byteswap.h" 3 4
# 1 "/usr/include/bits/wordsize.h" 1 3 4
# 29 "/usr/include/bits/byteswap.h" 2 3 4
# 62 "/usr/include/endian.h" 2 3 4
# 218 "/usr/include/sys/types.h" 2 3 4


# 1 "/usr/include/sys/select.h" 1 3 4
# 31 "/usr/include/sys/select.h" 3 4
# 1 "/usr/include/bits/select.h" 1 3 4
# 23 "/usr/include/bits/select.h" 3 4
# 1 "/usr/include/bits/wordsize.h" 1 3 4
# 24 "/usr/include/bits/select.h" 2 3 4
# 32 "/usr/include/sys/select.h" 2 3 4


# 1 "/usr/include/bits/sigset.h" 1 3 4
# 24 "/usr/include/bits/sigset.h" 3 4
typedef int __sig_atomic_t;




typedef struct
  {
    unsigned long int __val[(1024 / (8 * sizeof (unsigned long int)))];
  } __sigset_t;
# 35 "/usr/include/sys/select.h" 2 3 4



typedef __sigset_t sigset_t;





# 1 "/usr/include/time.h" 1 3 4
# 120 "/usr/include/time.h" 3 4
struct timespec
  {
    __time_t tv_sec;
    long int tv_nsec;
  };
# 45 "/usr/include/sys/select.h" 2 3 4

# 1 "/usr/include/bits/time.h" 1 3 4
# 75 "/usr/include/bits/time.h" 3 4
struct timeval
  {
    __time_t tv_sec;
    __suseconds_t tv_usec;
  };
# 47 "/usr/include/sys/select.h" 2 3 4


typedef __suseconds_t suseconds_t;





typedef long int __fd_mask;
# 67 "/usr/include/sys/select.h" 3 4
typedef struct
  {






    __fd_mask __fds_bits[1024 / (8 * (int) sizeof (__fd_mask))];


  } fd_set;






typedef __fd_mask fd_mask;
# 99 "/usr/include/sys/select.h" 3 4

# 109 "/usr/include/sys/select.h" 3 4
extern int select (int __nfds, fd_set *__restrict __readfds,
     fd_set *__restrict __writefds,
     fd_set *__restrict __exceptfds,
     struct timeval *__restrict __timeout);
# 121 "/usr/include/sys/select.h" 3 4
extern int pselect (int __nfds, fd_set *__restrict __readfds,
      fd_set *__restrict __writefds,
      fd_set *__restrict __exceptfds,
      const struct timespec *__restrict __timeout,
      const __sigset_t *__restrict __sigmask);



# 221 "/usr/include/sys/types.h" 2 3 4


# 1 "/usr/include/sys/sysmacros.h" 1 3 4
# 30 "/usr/include/sys/sysmacros.h" 3 4
__extension__
extern unsigned int gnu_dev_major (unsigned long long int __dev)
     __attribute__ ((__nothrow__));
__extension__
extern unsigned int gnu_dev_minor (unsigned long long int __dev)
     __attribute__ ((__nothrow__));
__extension__
extern unsigned long long int gnu_dev_makedev (unsigned int __major,
            unsigned int __minor)
     __attribute__ ((__nothrow__));
# 224 "/usr/include/sys/types.h" 2 3 4





typedef __blksize_t blksize_t;






typedef __blkcnt_t blkcnt_t;



typedef __fsblkcnt_t fsblkcnt_t;



typedef __fsfilcnt_t fsfilcnt_t;
# 271 "/usr/include/sys/types.h" 3 4
# 1 "/usr/include/bits/pthreadtypes.h" 1 3 4
# 23 "/usr/include/bits/pthreadtypes.h" 3 4
# 1 "/usr/include/bits/wordsize.h" 1 3 4
# 24 "/usr/include/bits/pthreadtypes.h" 2 3 4
# 50 "/usr/include/bits/pthreadtypes.h" 3 4
typedef unsigned long int pthread_t;


typedef union
{
  char __size[56];
  long int __align;
} pthread_attr_t;



typedef struct __pthread_internal_list
{
  struct __pthread_internal_list *__prev;
  struct __pthread_internal_list *__next;
} __pthread_list_t;
# 76 "/usr/include/bits/pthreadtypes.h" 3 4
typedef union
{
  struct __pthread_mutex_s
  {
    int __lock;
    unsigned int __count;
    int __owner;

    unsigned int __nusers;



    int __kind;

    int __spins;
    __pthread_list_t __list;
# 101 "/usr/include/bits/pthreadtypes.h" 3 4
  } __data;
  char __size[40];
  long int __align;
} pthread_mutex_t;

typedef union
{
  char __size[4];
  int __align;
} pthread_mutexattr_t;




typedef union
{
  struct
  {
    int __lock;
    unsigned int __futex;
    __extension__ unsigned long long int __total_seq;
    __extension__ unsigned long long int __wakeup_seq;
    __extension__ unsigned long long int __woken_seq;
    void *__mutex;
    unsigned int __nwaiters;
    unsigned int __broadcast_seq;
  } __data;
  char __size[48];
  __extension__ long long int __align;
} pthread_cond_t;

typedef union
{
  char __size[4];
  int __align;
} pthread_condattr_t;



typedef unsigned int pthread_key_t;



typedef int pthread_once_t;





typedef union
{

  struct
  {
    int __lock;
    unsigned int __nr_readers;
    unsigned int __readers_wakeup;
    unsigned int __writer_wakeup;
    unsigned int __nr_readers_queued;
    unsigned int __nr_writers_queued;
    int __writer;
    int __shared;
    unsigned long int __pad1;
    unsigned long int __pad2;


    unsigned int __flags;
  } __data;
# 187 "/usr/include/bits/pthreadtypes.h" 3 4
  char __size[56];
  long int __align;
} pthread_rwlock_t;

typedef union
{
  char __size[8];
  long int __align;
} pthread_rwlockattr_t;





typedef volatile int pthread_spinlock_t;




typedef union
{
  char __size[32];
  long int __align;
} pthread_barrier_t;

typedef union
{
  char __size[4];
  int __align;
} pthread_barrierattr_t;
# 272 "/usr/include/sys/types.h" 2 3 4



# 25 "/usr/include/sys/uio.h" 2 3 4




# 1 "/usr/include/bits/uio.h" 1 3 4
# 44 "/usr/include/bits/uio.h" 3 4
struct iovec
  {
    void *iov_base;
    size_t iov_len;
  };
# 30 "/usr/include/sys/uio.h" 2 3 4
# 40 "/usr/include/sys/uio.h" 3 4
extern ssize_t readv (int __fd, __const struct iovec *__iovec, int __count)
  ;
# 51 "/usr/include/sys/uio.h" 3 4
extern ssize_t writev (int __fd, __const struct iovec *__iovec, int __count)
  ;
# 66 "/usr/include/sys/uio.h" 3 4
extern ssize_t preadv (int __fd, __const struct iovec *__iovec, int __count,
         __off_t __offset) ;
# 78 "/usr/include/sys/uio.h" 3 4
extern ssize_t pwritev (int __fd, __const struct iovec *__iovec, int __count,
   __off_t __offset) ;
# 121 "/usr/include/sys/uio.h" 3 4

# 29 "/usr/include/sys/socket.h" 2 3 4

# 1 "/opt/rh/devtoolset-2/root/usr/lib/gcc/x86_64-redhat-linux/4.8.2/include/stddef.h" 1 3 4
# 31 "/usr/include/sys/socket.h" 2 3 4
# 40 "/usr/include/sys/socket.h" 3 4
# 1 "/usr/include/bits/socket.h" 1 3 4
# 29 "/usr/include/bits/socket.h" 3 4
# 1 "/opt/rh/devtoolset-2/root/usr/lib/gcc/x86_64-redhat-linux/4.8.2/include/stddef.h" 1 3 4
# 30 "/usr/include/bits/socket.h" 2 3 4





typedef __socklen_t socklen_t;




enum __socket_type
{
  SOCK_STREAM = 1,


  SOCK_DGRAM = 2,


  SOCK_RAW = 3,

  SOCK_RDM = 4,

  SOCK_SEQPACKET = 5,


  SOCK_DCCP = 6,

  SOCK_PACKET = 10,







  SOCK_CLOEXEC = 02000000,


  SOCK_NONBLOCK = 04000


};
# 171 "/usr/include/bits/socket.h" 3 4
# 1 "/usr/include/bits/sockaddr.h" 1 3 4
# 29 "/usr/include/bits/sockaddr.h" 3 4
typedef unsigned short int sa_family_t;
# 172 "/usr/include/bits/socket.h" 2 3 4


struct sockaddr
  {
    sa_family_t sa_family;
    char sa_data[14];
  };
# 187 "/usr/include/bits/socket.h" 3 4
struct sockaddr_storage
  {
    sa_family_t ss_family;
    unsigned long int __ss_align;
    char __ss_padding[(128 - (2 * sizeof (unsigned long int)))];
  };



enum
  {
    MSG_OOB = 0x01,

    MSG_PEEK = 0x02,

    MSG_DONTROUTE = 0x04,






    MSG_CTRUNC = 0x08,

    MSG_PROXY = 0x10,

    MSG_TRUNC = 0x20,

    MSG_DONTWAIT = 0x40,

    MSG_EOR = 0x80,

    MSG_WAITALL = 0x100,

    MSG_FIN = 0x200,

    MSG_SYN = 0x400,

    MSG_CONFIRM = 0x800,

    MSG_RST = 0x1000,

    MSG_ERRQUEUE = 0x2000,

    MSG_NOSIGNAL = 0x4000,

    MSG_MORE = 0x8000,

    MSG_WAITFORONE = 0x10000,


    MSG_CMSG_CLOEXEC = 0x40000000



  };




struct msghdr
  {
    void *msg_name;
    socklen_t msg_namelen;

    struct iovec *msg_iov;
    size_t msg_iovlen;

    void *msg_control;
    size_t msg_controllen;




    int msg_flags;
  };
# 274 "/usr/include/bits/socket.h" 3 4
struct cmsghdr
  {
    size_t cmsg_len;




    int cmsg_level;
    int cmsg_type;

    __extension__ unsigned char __cmsg_data [];

  };
# 304 "/usr/include/bits/socket.h" 3 4
extern struct cmsghdr *__cmsg_nxthdr (struct msghdr *__mhdr,
          struct cmsghdr *__cmsg) __attribute__ ((__nothrow__));
# 331 "/usr/include/bits/socket.h" 3 4
enum
  {
    SCM_RIGHTS = 0x01





  };
# 377 "/usr/include/bits/socket.h" 3 4
# 1 "/usr/include/asm/socket.h" 1 3 4
# 1 "/usr/include/asm-generic/socket.h" 1 3 4



# 1 "/usr/include/asm/sockios.h" 1 3 4
# 1 "/usr/include/asm-generic/sockios.h" 1 3 4
# 1 "/usr/include/asm/sockios.h" 2 3 4
# 5 "/usr/include/asm-generic/socket.h" 2 3 4
# 1 "/usr/include/asm/socket.h" 2 3 4
# 378 "/usr/include/bits/socket.h" 2 3 4
# 411 "/usr/include/bits/socket.h" 3 4
struct linger
  {
    int l_onoff;
    int l_linger;
  };









extern int recvmmsg (int __fd, struct mmsghdr *__vmessages,
       unsigned int __vlen, int __flags,
       __const struct timespec *__tmo);


# 41 "/usr/include/sys/socket.h" 2 3 4




struct osockaddr
  {
    unsigned short int sa_family;
    unsigned char sa_data[14];
  };




enum
{
  SHUT_RD = 0,

  SHUT_WR,

  SHUT_RDWR

};
# 105 "/usr/include/sys/socket.h" 3 4
extern int socket (int __domain, int __type, int __protocol) __attribute__ ((__nothrow__));





extern int socketpair (int __domain, int __type, int __protocol,
         int __fds[2]) __attribute__ ((__nothrow__));


extern int bind (int __fd, __const struct sockaddr * __addr, socklen_t __len)
     __attribute__ ((__nothrow__));


extern int getsockname (int __fd, struct sockaddr *__restrict __addr,
   socklen_t *__restrict __len) __attribute__ ((__nothrow__));
# 129 "/usr/include/sys/socket.h" 3 4
extern int connect (int __fd, __const struct sockaddr * __addr, socklen_t __len);



extern int getpeername (int __fd, struct sockaddr *__restrict __addr,
   socklen_t *__restrict __len) __attribute__ ((__nothrow__));






extern ssize_t send (int __fd, __const void *__buf, size_t __n, int __flags);






extern ssize_t recv (int __fd, void *__buf, size_t __n, int __flags);






extern ssize_t sendto (int __fd, __const void *__buf, size_t __n,
         int __flags, __const struct sockaddr * __addr,
         socklen_t __addr_len);
# 166 "/usr/include/sys/socket.h" 3 4
extern ssize_t recvfrom (int __fd, void *__restrict __buf, size_t __n,
    int __flags, struct sockaddr *__restrict __addr,
    socklen_t *__restrict __addr_len);







extern ssize_t sendmsg (int __fd, __const struct msghdr *__message,
   int __flags);






extern ssize_t recvmsg (int __fd, struct msghdr *__message, int __flags);





extern int getsockopt (int __fd, int __level, int __optname,
         void *__restrict __optval,
         socklen_t *__restrict __optlen) __attribute__ ((__nothrow__));




extern int setsockopt (int __fd, int __level, int __optname,
         __const void *__optval, socklen_t __optlen) __attribute__ ((__nothrow__));





extern int listen (int __fd, int __n) __attribute__ ((__nothrow__));
# 214 "/usr/include/sys/socket.h" 3 4
extern int accept (int __fd, struct sockaddr *__restrict __addr,
     socklen_t *__restrict __addr_len);
# 232 "/usr/include/sys/socket.h" 3 4
extern int shutdown (int __fd, int __how) __attribute__ ((__nothrow__));




extern int sockatmark (int __fd) __attribute__ ((__nothrow__));







extern int isfdtype (int __fd, int __fdtype) __attribute__ ((__nothrow__));
# 254 "/usr/include/sys/socket.h" 3 4

# 26 "/usr/include/netinet/in.h" 2 3 4






typedef uint32_t in_addr_t;
struct in_addr
  {
    in_addr_t s_addr;
  };


# 1 "/usr/include/bits/in.h" 1 3 4
# 111 "/usr/include/bits/in.h" 3 4
struct ip_opts
  {
    struct in_addr ip_dst;
    char ip_opts[40];
  };


struct ip_mreqn
  {
    struct in_addr imr_multiaddr;
    struct in_addr imr_address;
    int imr_ifindex;
  };


struct in_pktinfo
  {
    int ipi_ifindex;
    struct in_addr ipi_spec_dst;
    struct in_addr ipi_addr;
  };
# 40 "/usr/include/netinet/in.h" 2 3 4


enum
  {
    IPPROTO_IP = 0,

    IPPROTO_ICMP = 1,

    IPPROTO_IGMP = 2,

    IPPROTO_IPIP = 4,

    IPPROTO_TCP = 6,

    IPPROTO_EGP = 8,

    IPPROTO_PUP = 12,

    IPPROTO_UDP = 17,

    IPPROTO_IDP = 22,

    IPPROTO_TP = 29,

    IPPROTO_DCCP = 33,

    IPPROTO_IPV6 = 41,

    IPPROTO_RSVP = 46,

    IPPROTO_GRE = 47,

    IPPROTO_ESP = 50,

    IPPROTO_AH = 51,

    IPPROTO_MTP = 92,

    IPPROTO_BEETPH = 94,

    IPPROTO_ENCAP = 98,

    IPPROTO_PIM = 103,

    IPPROTO_COMP = 108,

    IPPROTO_SCTP = 132,

    IPPROTO_UDPLITE = 136,

    IPPROTO_RAW = 255,

    IPPROTO_MAX
  };





enum
  {
    IPPROTO_HOPOPTS = 0,

    IPPROTO_ROUTING = 43,

    IPPROTO_FRAGMENT = 44,

    IPPROTO_ICMPV6 = 58,

    IPPROTO_NONE = 59,

    IPPROTO_DSTOPTS = 60,

    IPPROTO_MH = 135,

  };



typedef uint16_t in_port_t;


enum
  {
    IPPORT_ECHO = 7,
    IPPORT_DISCARD = 9,
    IPPORT_SYSTAT = 11,
    IPPORT_DAYTIME = 13,
    IPPORT_NETSTAT = 15,
    IPPORT_FTP = 21,
    IPPORT_TELNET = 23,
    IPPORT_SMTP = 25,
    IPPORT_TIMESERVER = 37,
    IPPORT_NAMESERVER = 42,
    IPPORT_WHOIS = 43,
    IPPORT_MTP = 57,

    IPPORT_TFTP = 69,
    IPPORT_RJE = 77,
    IPPORT_FINGER = 79,
    IPPORT_TTYLINK = 87,
    IPPORT_SUPDUP = 95,


    IPPORT_EXECSERVER = 512,
    IPPORT_LOGINSERVER = 513,
    IPPORT_CMDSERVER = 514,
    IPPORT_EFSSERVER = 520,


    IPPORT_BIFFUDP = 512,
    IPPORT_WHOSERVER = 513,
    IPPORT_ROUTESERVER = 520,


    IPPORT_RESERVED = 1024,


    IPPORT_USERRESERVED = 5000
  };
# 211 "/usr/include/netinet/in.h" 3 4
struct in6_addr
  {
    union
      {
 uint8_t __u6_addr8[16];

 uint16_t __u6_addr16[8];
 uint32_t __u6_addr32[4];

      } __in6_u;





  };


extern const struct in6_addr in6addr_any;
extern const struct in6_addr in6addr_loopback;
# 239 "/usr/include/netinet/in.h" 3 4
struct sockaddr_in
  {
    sa_family_t sin_family;
    in_port_t sin_port;
    struct in_addr sin_addr;


    unsigned char sin_zero[sizeof (struct sockaddr) -
      (sizeof (unsigned short int)) -
      sizeof (in_port_t) -
      sizeof (struct in_addr)];
  };



struct sockaddr_in6
  {
    sa_family_t sin6_family;
    in_port_t sin6_port;
    uint32_t sin6_flowinfo;
    struct in6_addr sin6_addr;
    uint32_t sin6_scope_id;
  };




struct ip_mreq
  {

    struct in_addr imr_multiaddr;


    struct in_addr imr_interface;
  };

struct ip_mreq_source
  {

    struct in_addr imr_multiaddr;


    struct in_addr imr_interface;


    struct in_addr imr_sourceaddr;
  };




struct ipv6_mreq
  {

    struct in6_addr ipv6mr_multiaddr;


    unsigned int ipv6mr_interface;
  };




struct group_req
  {

    uint32_t gr_interface;


    struct sockaddr_storage gr_group;
  };

struct group_source_req
  {

    uint32_t gsr_interface;


    struct sockaddr_storage gsr_group;


    struct sockaddr_storage gsr_source;
  };



struct ip_msfilter
  {

    struct in_addr imsf_multiaddr;


    struct in_addr imsf_interface;


    uint32_t imsf_fmode;


    uint32_t imsf_numsrc;

    struct in_addr imsf_slist[1];
  };





struct group_filter
  {

    uint32_t gf_interface;


    struct sockaddr_storage gf_group;


    uint32_t gf_fmode;


    uint32_t gf_numsrc;

    struct sockaddr_storage gf_slist[1];
};
# 376 "/usr/include/netinet/in.h" 3 4
extern uint32_t ntohl (uint32_t __netlong) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern uint16_t ntohs (uint16_t __netshort)
     __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern uint32_t htonl (uint32_t __hostlong)
     __attribute__ ((__nothrow__)) __attribute__ ((__const__));
extern uint16_t htons (uint16_t __hostshort)
     __attribute__ ((__nothrow__)) __attribute__ ((__const__));




# 1 "/usr/include/bits/byteswap.h" 1 3 4
# 388 "/usr/include/netinet/in.h" 2 3 4
# 451 "/usr/include/netinet/in.h" 3 4
extern int bindresvport (int __sockfd, struct sockaddr_in *__sock_in) __attribute__ ((__nothrow__));


extern int bindresvport6 (int __sockfd, struct sockaddr_in6 *__sock_in)
     __attribute__ ((__nothrow__));
# 576 "/usr/include/netinet/in.h" 3 4

# 7 "lib/http.h" 2






typedef enum
{
    lib_http_error_contex = 1,
    lib_http_error_dns,
    lib_http_error_fail_connect,
    lib_http_error_fail_ssl_connect,
    lib_http_error_fail_http_connect,
    lib_http_error_fail_http_error,
    lib_http_error_fail_io_error,
}lib_http_errors_t;

typedef enum
{
    lib_http_wait_write,
    lib_http_wait_read
}lib_http_wait_t;


void lib_http_clear_context(void *ctx);
int lib_http_open(void *ctx, int closeConnection, const char *uri, const char *user_agent, const char *content_type, const char *cookie, const char *post_data, int64_t offset, char *resource, unsigned int resource_len, struct sockaddr_in *interface);
int lib_http_open_first(void *ctx, int closeConnection, const char *uri, const char *user_agent, int64_t offset, char *resource, unsigned int resource_len, struct sockaddr_in *interface, lib_http_wait_t *waitinfo);
int lib_http_open_second(void *ctx, int *connected, lib_http_wait_t *waitinfo);
void lib_http_url_split(char *proto, int proto_size, char *authorization, int authorization_size, char *hostname, int hostname_size, int *port_ptr, char *path, int path_size, const char *url, int *https_proto);

int lib_http_read(void *ctx, char *buf, int size);
int lib_http_check_fill(void *ctx, _Bool flush);
int lib_http_get_fd(void *ctx);
void lib_http_copy_connection(void *dst, void *src);
_Bool lib_http_is_keepalive(void *ctx);
void lib_http_close(void *ctx);
int64_t lib_http_get_filesize(void *ctx);
uint32_t lib_get_http_context_size(void);
# 2 "lib/http.c" 2
# 1 "/usr/include/unistd.h" 1 3 4
# 28 "/usr/include/unistd.h" 3 4

# 203 "/usr/include/unistd.h" 3 4
# 1 "/usr/include/bits/posix_opt.h" 1 3 4
# 204 "/usr/include/unistd.h" 2 3 4



# 1 "/usr/include/bits/environments.h" 1 3 4
# 23 "/usr/include/bits/environments.h" 3 4
# 1 "/usr/include/bits/wordsize.h" 1 3 4
# 24 "/usr/include/bits/environments.h" 2 3 4
# 208 "/usr/include/unistd.h" 2 3 4
# 227 "/usr/include/unistd.h" 3 4
# 1 "/opt/rh/devtoolset-2/root/usr/lib/gcc/x86_64-redhat-linux/4.8.2/include/stddef.h" 1 3 4
# 228 "/usr/include/unistd.h" 2 3 4
# 256 "/usr/include/unistd.h" 3 4
typedef __useconds_t useconds_t;
# 288 "/usr/include/unistd.h" 3 4
extern int access (__const char *__name, int __type) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
# 305 "/usr/include/unistd.h" 3 4
extern int faccessat (int __fd, __const char *__file, int __type, int __flag)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2))) ;
# 331 "/usr/include/unistd.h" 3 4
extern __off_t lseek (int __fd, __off_t __offset, int __whence) __attribute__ ((__nothrow__));
# 350 "/usr/include/unistd.h" 3 4
extern int close (int __fd);






extern ssize_t read (int __fd, void *__buf, size_t __nbytes) ;





extern ssize_t write (int __fd, __const void *__buf, size_t __n) ;
# 373 "/usr/include/unistd.h" 3 4
extern ssize_t pread (int __fd, void *__buf, size_t __nbytes,
        __off_t __offset) ;






extern ssize_t pwrite (int __fd, __const void *__buf, size_t __n,
         __off_t __offset) ;
# 414 "/usr/include/unistd.h" 3 4
extern int pipe (int __pipedes[2]) __attribute__ ((__nothrow__)) ;
# 429 "/usr/include/unistd.h" 3 4
extern unsigned int alarm (unsigned int __seconds) __attribute__ ((__nothrow__));
# 441 "/usr/include/unistd.h" 3 4
extern unsigned int sleep (unsigned int __seconds);







extern __useconds_t ualarm (__useconds_t __value, __useconds_t __interval)
     __attribute__ ((__nothrow__));






extern int usleep (__useconds_t __useconds);
# 466 "/usr/include/unistd.h" 3 4
extern int pause (void);



extern int chown (__const char *__file, __uid_t __owner, __gid_t __group)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;



extern int fchown (int __fd, __uid_t __owner, __gid_t __group) __attribute__ ((__nothrow__)) ;




extern int lchown (__const char *__file, __uid_t __owner, __gid_t __group)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;






extern int fchownat (int __fd, __const char *__file, __uid_t __owner,
       __gid_t __group, int __flag)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2))) ;



extern int chdir (__const char *__path) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;



extern int fchdir (int __fd) __attribute__ ((__nothrow__)) ;
# 508 "/usr/include/unistd.h" 3 4
extern char *getcwd (char *__buf, size_t __size) __attribute__ ((__nothrow__)) ;
# 522 "/usr/include/unistd.h" 3 4
extern char *getwd (char *__buf)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) __attribute__ ((__deprecated__)) ;




extern int dup (int __fd) __attribute__ ((__nothrow__)) ;


extern int dup2 (int __fd, int __fd2) __attribute__ ((__nothrow__));
# 540 "/usr/include/unistd.h" 3 4
extern char **__environ;







extern int execve (__const char *__path, char *__const __argv[],
     char *__const __envp[]) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));




extern int fexecve (int __fd, char *__const __argv[], char *__const __envp[])
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2)));




extern int execv (__const char *__path, char *__const __argv[])
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));



extern int execle (__const char *__path, __const char *__arg, ...)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));



extern int execl (__const char *__path, __const char *__arg, ...)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));



extern int execvp (__const char *__file, char *__const __argv[])
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));




extern int execlp (__const char *__file, __const char *__arg, ...)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
# 595 "/usr/include/unistd.h" 3 4
extern int nice (int __inc) __attribute__ ((__nothrow__)) ;




extern void _exit (int __status) __attribute__ ((__noreturn__));





# 1 "/usr/include/bits/confname.h" 1 3 4
# 26 "/usr/include/bits/confname.h" 3 4
enum
  {
    _PC_LINK_MAX,

    _PC_MAX_CANON,

    _PC_MAX_INPUT,

    _PC_NAME_MAX,

    _PC_PATH_MAX,

    _PC_PIPE_BUF,

    _PC_CHOWN_RESTRICTED,

    _PC_NO_TRUNC,

    _PC_VDISABLE,

    _PC_SYNC_IO,

    _PC_ASYNC_IO,

    _PC_PRIO_IO,

    _PC_SOCK_MAXBUF,

    _PC_FILESIZEBITS,

    _PC_REC_INCR_XFER_SIZE,

    _PC_REC_MAX_XFER_SIZE,

    _PC_REC_MIN_XFER_SIZE,

    _PC_REC_XFER_ALIGN,

    _PC_ALLOC_SIZE_MIN,

    _PC_SYMLINK_MAX,

    _PC_2_SYMLINKS

  };


enum
  {
    _SC_ARG_MAX,

    _SC_CHILD_MAX,

    _SC_CLK_TCK,

    _SC_NGROUPS_MAX,

    _SC_OPEN_MAX,

    _SC_STREAM_MAX,

    _SC_TZNAME_MAX,

    _SC_JOB_CONTROL,

    _SC_SAVED_IDS,

    _SC_REALTIME_SIGNALS,

    _SC_PRIORITY_SCHEDULING,

    _SC_TIMERS,

    _SC_ASYNCHRONOUS_IO,

    _SC_PRIORITIZED_IO,

    _SC_SYNCHRONIZED_IO,

    _SC_FSYNC,

    _SC_MAPPED_FILES,

    _SC_MEMLOCK,

    _SC_MEMLOCK_RANGE,

    _SC_MEMORY_PROTECTION,

    _SC_MESSAGE_PASSING,

    _SC_SEMAPHORES,

    _SC_SHARED_MEMORY_OBJECTS,

    _SC_AIO_LISTIO_MAX,

    _SC_AIO_MAX,

    _SC_AIO_PRIO_DELTA_MAX,

    _SC_DELAYTIMER_MAX,

    _SC_MQ_OPEN_MAX,

    _SC_MQ_PRIO_MAX,

    _SC_VERSION,

    _SC_PAGESIZE,


    _SC_RTSIG_MAX,

    _SC_SEM_NSEMS_MAX,

    _SC_SEM_VALUE_MAX,

    _SC_SIGQUEUE_MAX,

    _SC_TIMER_MAX,




    _SC_BC_BASE_MAX,

    _SC_BC_DIM_MAX,

    _SC_BC_SCALE_MAX,

    _SC_BC_STRING_MAX,

    _SC_COLL_WEIGHTS_MAX,

    _SC_EQUIV_CLASS_MAX,

    _SC_EXPR_NEST_MAX,

    _SC_LINE_MAX,

    _SC_RE_DUP_MAX,

    _SC_CHARCLASS_NAME_MAX,


    _SC_2_VERSION,

    _SC_2_C_BIND,

    _SC_2_C_DEV,

    _SC_2_FORT_DEV,

    _SC_2_FORT_RUN,

    _SC_2_SW_DEV,

    _SC_2_LOCALEDEF,


    _SC_PII,

    _SC_PII_XTI,

    _SC_PII_SOCKET,

    _SC_PII_INTERNET,

    _SC_PII_OSI,

    _SC_POLL,

    _SC_SELECT,

    _SC_UIO_MAXIOV,

    _SC_IOV_MAX = _SC_UIO_MAXIOV,

    _SC_PII_INTERNET_STREAM,

    _SC_PII_INTERNET_DGRAM,

    _SC_PII_OSI_COTS,

    _SC_PII_OSI_CLTS,

    _SC_PII_OSI_M,

    _SC_T_IOV_MAX,



    _SC_THREADS,

    _SC_THREAD_SAFE_FUNCTIONS,

    _SC_GETGR_R_SIZE_MAX,

    _SC_GETPW_R_SIZE_MAX,

    _SC_LOGIN_NAME_MAX,

    _SC_TTY_NAME_MAX,

    _SC_THREAD_DESTRUCTOR_ITERATIONS,

    _SC_THREAD_KEYS_MAX,

    _SC_THREAD_STACK_MIN,

    _SC_THREAD_THREADS_MAX,

    _SC_THREAD_ATTR_STACKADDR,

    _SC_THREAD_ATTR_STACKSIZE,

    _SC_THREAD_PRIORITY_SCHEDULING,

    _SC_THREAD_PRIO_INHERIT,

    _SC_THREAD_PRIO_PROTECT,

    _SC_THREAD_PROCESS_SHARED,


    _SC_NPROCESSORS_CONF,

    _SC_NPROCESSORS_ONLN,

    _SC_PHYS_PAGES,

    _SC_AVPHYS_PAGES,

    _SC_ATEXIT_MAX,

    _SC_PASS_MAX,


    _SC_XOPEN_VERSION,

    _SC_XOPEN_XCU_VERSION,

    _SC_XOPEN_UNIX,

    _SC_XOPEN_CRYPT,

    _SC_XOPEN_ENH_I18N,

    _SC_XOPEN_SHM,


    _SC_2_CHAR_TERM,

    _SC_2_C_VERSION,

    _SC_2_UPE,


    _SC_XOPEN_XPG2,

    _SC_XOPEN_XPG3,

    _SC_XOPEN_XPG4,


    _SC_CHAR_BIT,

    _SC_CHAR_MAX,

    _SC_CHAR_MIN,

    _SC_INT_MAX,

    _SC_INT_MIN,

    _SC_LONG_BIT,

    _SC_WORD_BIT,

    _SC_MB_LEN_MAX,

    _SC_NZERO,

    _SC_SSIZE_MAX,

    _SC_SCHAR_MAX,

    _SC_SCHAR_MIN,

    _SC_SHRT_MAX,

    _SC_SHRT_MIN,

    _SC_UCHAR_MAX,

    _SC_UINT_MAX,

    _SC_ULONG_MAX,

    _SC_USHRT_MAX,


    _SC_NL_ARGMAX,

    _SC_NL_LANGMAX,

    _SC_NL_MSGMAX,

    _SC_NL_NMAX,

    _SC_NL_SETMAX,

    _SC_NL_TEXTMAX,


    _SC_XBS5_ILP32_OFF32,

    _SC_XBS5_ILP32_OFFBIG,

    _SC_XBS5_LP64_OFF64,

    _SC_XBS5_LPBIG_OFFBIG,


    _SC_XOPEN_LEGACY,

    _SC_XOPEN_REALTIME,

    _SC_XOPEN_REALTIME_THREADS,


    _SC_ADVISORY_INFO,

    _SC_BARRIERS,

    _SC_BASE,

    _SC_C_LANG_SUPPORT,

    _SC_C_LANG_SUPPORT_R,

    _SC_CLOCK_SELECTION,

    _SC_CPUTIME,

    _SC_THREAD_CPUTIME,

    _SC_DEVICE_IO,

    _SC_DEVICE_SPECIFIC,

    _SC_DEVICE_SPECIFIC_R,

    _SC_FD_MGMT,

    _SC_FIFO,

    _SC_PIPE,

    _SC_FILE_ATTRIBUTES,

    _SC_FILE_LOCKING,

    _SC_FILE_SYSTEM,

    _SC_MONOTONIC_CLOCK,

    _SC_MULTI_PROCESS,

    _SC_SINGLE_PROCESS,

    _SC_NETWORKING,

    _SC_READER_WRITER_LOCKS,

    _SC_SPIN_LOCKS,

    _SC_REGEXP,

    _SC_REGEX_VERSION,

    _SC_SHELL,

    _SC_SIGNALS,

    _SC_SPAWN,

    _SC_SPORADIC_SERVER,

    _SC_THREAD_SPORADIC_SERVER,

    _SC_SYSTEM_DATABASE,

    _SC_SYSTEM_DATABASE_R,

    _SC_TIMEOUTS,

    _SC_TYPED_MEMORY_OBJECTS,

    _SC_USER_GROUPS,

    _SC_USER_GROUPS_R,

    _SC_2_PBS,

    _SC_2_PBS_ACCOUNTING,

    _SC_2_PBS_LOCATE,

    _SC_2_PBS_MESSAGE,

    _SC_2_PBS_TRACK,

    _SC_SYMLOOP_MAX,

    _SC_STREAMS,

    _SC_2_PBS_CHECKPOINT,


    _SC_V6_ILP32_OFF32,

    _SC_V6_ILP32_OFFBIG,

    _SC_V6_LP64_OFF64,

    _SC_V6_LPBIG_OFFBIG,


    _SC_HOST_NAME_MAX,

    _SC_TRACE,

    _SC_TRACE_EVENT_FILTER,

    _SC_TRACE_INHERIT,

    _SC_TRACE_LOG,


    _SC_LEVEL1_ICACHE_SIZE,

    _SC_LEVEL1_ICACHE_ASSOC,

    _SC_LEVEL1_ICACHE_LINESIZE,

    _SC_LEVEL1_DCACHE_SIZE,

    _SC_LEVEL1_DCACHE_ASSOC,

    _SC_LEVEL1_DCACHE_LINESIZE,

    _SC_LEVEL2_CACHE_SIZE,

    _SC_LEVEL2_CACHE_ASSOC,

    _SC_LEVEL2_CACHE_LINESIZE,

    _SC_LEVEL3_CACHE_SIZE,

    _SC_LEVEL3_CACHE_ASSOC,

    _SC_LEVEL3_CACHE_LINESIZE,

    _SC_LEVEL4_CACHE_SIZE,

    _SC_LEVEL4_CACHE_ASSOC,

    _SC_LEVEL4_CACHE_LINESIZE,



    _SC_IPV6 = _SC_LEVEL1_ICACHE_SIZE + 50,

    _SC_RAW_SOCKETS,


    _SC_V7_ILP32_OFF32,

    _SC_V7_ILP32_OFFBIG,

    _SC_V7_LP64_OFF64,

    _SC_V7_LPBIG_OFFBIG,


    _SC_SS_REPL_MAX,


    _SC_TRACE_EVENT_NAME_MAX,

    _SC_TRACE_NAME_MAX,

    _SC_TRACE_SYS_MAX,

    _SC_TRACE_USER_EVENT_MAX,


    _SC_XOPEN_STREAMS,


    _SC_THREAD_ROBUST_PRIO_INHERIT,

    _SC_THREAD_ROBUST_PRIO_PROTECT

  };


enum
  {
    _CS_PATH,


    _CS_V6_WIDTH_RESTRICTED_ENVS,



    _CS_GNU_LIBC_VERSION,

    _CS_GNU_LIBPTHREAD_VERSION,


    _CS_V5_WIDTH_RESTRICTED_ENVS,



    _CS_V7_WIDTH_RESTRICTED_ENVS,



    _CS_LFS_CFLAGS = 1000,

    _CS_LFS_LDFLAGS,

    _CS_LFS_LIBS,

    _CS_LFS_LINTFLAGS,

    _CS_LFS64_CFLAGS,

    _CS_LFS64_LDFLAGS,

    _CS_LFS64_LIBS,

    _CS_LFS64_LINTFLAGS,


    _CS_XBS5_ILP32_OFF32_CFLAGS = 1100,

    _CS_XBS5_ILP32_OFF32_LDFLAGS,

    _CS_XBS5_ILP32_OFF32_LIBS,

    _CS_XBS5_ILP32_OFF32_LINTFLAGS,

    _CS_XBS5_ILP32_OFFBIG_CFLAGS,

    _CS_XBS5_ILP32_OFFBIG_LDFLAGS,

    _CS_XBS5_ILP32_OFFBIG_LIBS,

    _CS_XBS5_ILP32_OFFBIG_LINTFLAGS,

    _CS_XBS5_LP64_OFF64_CFLAGS,

    _CS_XBS5_LP64_OFF64_LDFLAGS,

    _CS_XBS5_LP64_OFF64_LIBS,

    _CS_XBS5_LP64_OFF64_LINTFLAGS,

    _CS_XBS5_LPBIG_OFFBIG_CFLAGS,

    _CS_XBS5_LPBIG_OFFBIG_LDFLAGS,

    _CS_XBS5_LPBIG_OFFBIG_LIBS,

    _CS_XBS5_LPBIG_OFFBIG_LINTFLAGS,


    _CS_POSIX_V6_ILP32_OFF32_CFLAGS,

    _CS_POSIX_V6_ILP32_OFF32_LDFLAGS,

    _CS_POSIX_V6_ILP32_OFF32_LIBS,

    _CS_POSIX_V6_ILP32_OFF32_LINTFLAGS,

    _CS_POSIX_V6_ILP32_OFFBIG_CFLAGS,

    _CS_POSIX_V6_ILP32_OFFBIG_LDFLAGS,

    _CS_POSIX_V6_ILP32_OFFBIG_LIBS,

    _CS_POSIX_V6_ILP32_OFFBIG_LINTFLAGS,

    _CS_POSIX_V6_LP64_OFF64_CFLAGS,

    _CS_POSIX_V6_LP64_OFF64_LDFLAGS,

    _CS_POSIX_V6_LP64_OFF64_LIBS,

    _CS_POSIX_V6_LP64_OFF64_LINTFLAGS,

    _CS_POSIX_V6_LPBIG_OFFBIG_CFLAGS,

    _CS_POSIX_V6_LPBIG_OFFBIG_LDFLAGS,

    _CS_POSIX_V6_LPBIG_OFFBIG_LIBS,

    _CS_POSIX_V6_LPBIG_OFFBIG_LINTFLAGS,


    _CS_POSIX_V7_ILP32_OFF32_CFLAGS,

    _CS_POSIX_V7_ILP32_OFF32_LDFLAGS,

    _CS_POSIX_V7_ILP32_OFF32_LIBS,

    _CS_POSIX_V7_ILP32_OFF32_LINTFLAGS,

    _CS_POSIX_V7_ILP32_OFFBIG_CFLAGS,

    _CS_POSIX_V7_ILP32_OFFBIG_LDFLAGS,

    _CS_POSIX_V7_ILP32_OFFBIG_LIBS,

    _CS_POSIX_V7_ILP32_OFFBIG_LINTFLAGS,

    _CS_POSIX_V7_LP64_OFF64_CFLAGS,

    _CS_POSIX_V7_LP64_OFF64_LDFLAGS,

    _CS_POSIX_V7_LP64_OFF64_LIBS,

    _CS_POSIX_V7_LP64_OFF64_LINTFLAGS,

    _CS_POSIX_V7_LPBIG_OFFBIG_CFLAGS,

    _CS_POSIX_V7_LPBIG_OFFBIG_LDFLAGS,

    _CS_POSIX_V7_LPBIG_OFFBIG_LIBS,

    _CS_POSIX_V7_LPBIG_OFFBIG_LINTFLAGS,


    _CS_V6_ENV,

    _CS_V7_ENV

  };
# 607 "/usr/include/unistd.h" 2 3 4


extern long int pathconf (__const char *__path, int __name)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));


extern long int fpathconf (int __fd, int __name) __attribute__ ((__nothrow__));


extern long int sysconf (int __name) __attribute__ ((__nothrow__));



extern size_t confstr (int __name, char *__buf, size_t __len) __attribute__ ((__nothrow__));




extern __pid_t getpid (void) __attribute__ ((__nothrow__));


extern __pid_t getppid (void) __attribute__ ((__nothrow__));




extern __pid_t getpgrp (void) __attribute__ ((__nothrow__));
# 643 "/usr/include/unistd.h" 3 4
extern __pid_t __getpgid (__pid_t __pid) __attribute__ ((__nothrow__));

extern __pid_t getpgid (__pid_t __pid) __attribute__ ((__nothrow__));






extern int setpgid (__pid_t __pid, __pid_t __pgid) __attribute__ ((__nothrow__));
# 669 "/usr/include/unistd.h" 3 4
extern int setpgrp (void) __attribute__ ((__nothrow__));
# 686 "/usr/include/unistd.h" 3 4
extern __pid_t setsid (void) __attribute__ ((__nothrow__));



extern __pid_t getsid (__pid_t __pid) __attribute__ ((__nothrow__));



extern __uid_t getuid (void) __attribute__ ((__nothrow__));


extern __uid_t geteuid (void) __attribute__ ((__nothrow__));


extern __gid_t getgid (void) __attribute__ ((__nothrow__));


extern __gid_t getegid (void) __attribute__ ((__nothrow__));




extern int getgroups (int __size, __gid_t __list[]) __attribute__ ((__nothrow__)) ;
# 719 "/usr/include/unistd.h" 3 4
extern int setuid (__uid_t __uid) __attribute__ ((__nothrow__));




extern int setreuid (__uid_t __ruid, __uid_t __euid) __attribute__ ((__nothrow__));




extern int seteuid (__uid_t __uid) __attribute__ ((__nothrow__));






extern int setgid (__gid_t __gid) __attribute__ ((__nothrow__));




extern int setregid (__gid_t __rgid, __gid_t __egid) __attribute__ ((__nothrow__));




extern int setegid (__gid_t __gid) __attribute__ ((__nothrow__));
# 775 "/usr/include/unistd.h" 3 4
extern __pid_t fork (void) __attribute__ ((__nothrow__));







extern __pid_t vfork (void) __attribute__ ((__nothrow__));





extern char *ttyname (int __fd) __attribute__ ((__nothrow__));



extern int ttyname_r (int __fd, char *__buf, size_t __buflen)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2))) ;



extern int isatty (int __fd) __attribute__ ((__nothrow__));





extern int ttyslot (void) __attribute__ ((__nothrow__));




extern int link (__const char *__from, __const char *__to)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2))) ;




extern int linkat (int __fromfd, __const char *__from, int __tofd,
     __const char *__to, int __flags)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2, 4))) ;




extern int symlink (__const char *__from, __const char *__to)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2))) ;




extern ssize_t readlink (__const char *__restrict __path,
    char *__restrict __buf, size_t __len)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2))) ;




extern int symlinkat (__const char *__from, int __tofd,
        __const char *__to) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 3))) ;


extern ssize_t readlinkat (int __fd, __const char *__restrict __path,
      char *__restrict __buf, size_t __len)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2, 3))) ;



extern int unlink (__const char *__name) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));



extern int unlinkat (int __fd, __const char *__name, int __flag)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2)));



extern int rmdir (__const char *__path) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));



extern __pid_t tcgetpgrp (int __fd) __attribute__ ((__nothrow__));


extern int tcsetpgrp (int __fd, __pid_t __pgrp_id) __attribute__ ((__nothrow__));






extern char *getlogin (void);







extern int getlogin_r (char *__name, size_t __name_len) __attribute__ ((__nonnull__ (1)));




extern int setlogin (__const char *__name) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
# 890 "/usr/include/unistd.h" 3 4
# 1 "/usr/include/getopt.h" 1 3 4
# 59 "/usr/include/getopt.h" 3 4
extern char *optarg;
# 73 "/usr/include/getopt.h" 3 4
extern int optind;




extern int opterr;



extern int optopt;
# 152 "/usr/include/getopt.h" 3 4
extern int getopt (int ___argc, char *const *___argv, const char *__shortopts)
       __attribute__ ((__nothrow__));
# 891 "/usr/include/unistd.h" 2 3 4







extern int gethostname (char *__name, size_t __len) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));






extern int sethostname (__const char *__name, size_t __len)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;



extern int sethostid (long int __id) __attribute__ ((__nothrow__)) ;





extern int getdomainname (char *__name, size_t __len)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;
extern int setdomainname (__const char *__name, size_t __len)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;





extern int vhangup (void) __attribute__ ((__nothrow__));


extern int revoke (__const char *__file) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;







extern int profil (unsigned short int *__sample_buffer, size_t __size,
     size_t __offset, unsigned int __scale)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));





extern int acct (__const char *__name) __attribute__ ((__nothrow__));



extern char *getusershell (void) __attribute__ ((__nothrow__));
extern void endusershell (void) __attribute__ ((__nothrow__));
extern void setusershell (void) __attribute__ ((__nothrow__));





extern int daemon (int __nochdir, int __noclose) __attribute__ ((__nothrow__)) ;






extern int chroot (__const char *__path) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;



extern char *getpass (__const char *__prompt) __attribute__ ((__nonnull__ (1)));
# 976 "/usr/include/unistd.h" 3 4
extern int fsync (int __fd);






extern long int gethostid (void);


extern void sync (void) __attribute__ ((__nothrow__));





extern int getpagesize (void) __attribute__ ((__nothrow__)) __attribute__ ((__const__));




extern int getdtablesize (void) __attribute__ ((__nothrow__));
# 1007 "/usr/include/unistd.h" 3 4
extern int truncate (__const char *__file, __off_t __length)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;
# 1026 "/usr/include/unistd.h" 3 4
extern int ftruncate (int __fd, __off_t __length) __attribute__ ((__nothrow__)) ;
# 1047 "/usr/include/unistd.h" 3 4
extern int brk (void *__addr) __attribute__ ((__nothrow__)) ;





extern void *sbrk (intptr_t __delta) __attribute__ ((__nothrow__));
# 1068 "/usr/include/unistd.h" 3 4
extern long int syscall (long int __sysno, ...) __attribute__ ((__nothrow__));
# 1091 "/usr/include/unistd.h" 3 4
extern int lockf (int __fd, int __cmd, __off_t __len) ;
# 1122 "/usr/include/unistd.h" 3 4
extern int fdatasync (int __fildes);
# 1151 "/usr/include/unistd.h" 3 4
extern char *ctermid (char *__s) __attribute__ ((__nothrow__));
# 1160 "/usr/include/unistd.h" 3 4

# 3 "lib/http.c" 2
# 1 "/usr/include/stdio.h" 1 3 4
# 30 "/usr/include/stdio.h" 3 4




# 1 "/opt/rh/devtoolset-2/root/usr/lib/gcc/x86_64-redhat-linux/4.8.2/include/stddef.h" 1 3 4
# 35 "/usr/include/stdio.h" 2 3 4
# 45 "/usr/include/stdio.h" 3 4
struct _IO_FILE;



typedef struct _IO_FILE FILE;





# 65 "/usr/include/stdio.h" 3 4
typedef struct _IO_FILE __FILE;
# 75 "/usr/include/stdio.h" 3 4
# 1 "/usr/include/libio.h" 1 3 4
# 32 "/usr/include/libio.h" 3 4
# 1 "/usr/include/_G_config.h" 1 3 4
# 15 "/usr/include/_G_config.h" 3 4
# 1 "/opt/rh/devtoolset-2/root/usr/lib/gcc/x86_64-redhat-linux/4.8.2/include/stddef.h" 1 3 4
# 16 "/usr/include/_G_config.h" 2 3 4




# 1 "/usr/include/wchar.h" 1 3 4
# 83 "/usr/include/wchar.h" 3 4
typedef struct
{
  int __count;
  union
  {

    unsigned int __wch;



    char __wchb[4];
  } __value;
} __mbstate_t;
# 21 "/usr/include/_G_config.h" 2 3 4

typedef struct
{
  __off_t __pos;
  __mbstate_t __state;
} _G_fpos_t;
typedef struct
{
  __off64_t __pos;
  __mbstate_t __state;
} _G_fpos64_t;
# 53 "/usr/include/_G_config.h" 3 4
typedef int _G_int16_t __attribute__ ((__mode__ (__HI__)));
typedef int _G_int32_t __attribute__ ((__mode__ (__SI__)));
typedef unsigned int _G_uint16_t __attribute__ ((__mode__ (__HI__)));
typedef unsigned int _G_uint32_t __attribute__ ((__mode__ (__SI__)));
# 33 "/usr/include/libio.h" 2 3 4
# 53 "/usr/include/libio.h" 3 4
# 1 "/opt/rh/devtoolset-2/root/usr/lib/gcc/x86_64-redhat-linux/4.8.2/include/stdarg.h" 1 3 4
# 40 "/opt/rh/devtoolset-2/root/usr/lib/gcc/x86_64-redhat-linux/4.8.2/include/stdarg.h" 3 4
typedef __builtin_va_list __gnuc_va_list;
# 54 "/usr/include/libio.h" 2 3 4
# 170 "/usr/include/libio.h" 3 4
struct _IO_jump_t; struct _IO_FILE;
# 180 "/usr/include/libio.h" 3 4
typedef void _IO_lock_t;





struct _IO_marker {
  struct _IO_marker *_next;
  struct _IO_FILE *_sbuf;



  int _pos;
# 203 "/usr/include/libio.h" 3 4
};


enum __codecvt_result
{
  __codecvt_ok,
  __codecvt_partial,
  __codecvt_error,
  __codecvt_noconv
};
# 271 "/usr/include/libio.h" 3 4
struct _IO_FILE {
  int _flags;




  char* _IO_read_ptr;
  char* _IO_read_end;
  char* _IO_read_base;
  char* _IO_write_base;
  char* _IO_write_ptr;
  char* _IO_write_end;
  char* _IO_buf_base;
  char* _IO_buf_end;

  char *_IO_save_base;
  char *_IO_backup_base;
  char *_IO_save_end;

  struct _IO_marker *_markers;

  struct _IO_FILE *_chain;

  int _fileno;



  int _flags2;

  __off_t _old_offset;



  unsigned short _cur_column;
  signed char _vtable_offset;
  char _shortbuf[1];



  _IO_lock_t *_lock;
# 319 "/usr/include/libio.h" 3 4
  __off64_t _offset;
# 328 "/usr/include/libio.h" 3 4
  void *__pad1;
  void *__pad2;
  void *__pad3;
  void *__pad4;
  size_t __pad5;

  int _mode;

  char _unused2[15 * sizeof (int) - 4 * sizeof (void *) - sizeof (size_t)];

};


typedef struct _IO_FILE _IO_FILE;


struct _IO_FILE_plus;

extern struct _IO_FILE_plus _IO_2_1_stdin_;
extern struct _IO_FILE_plus _IO_2_1_stdout_;
extern struct _IO_FILE_plus _IO_2_1_stderr_;
# 364 "/usr/include/libio.h" 3 4
typedef __ssize_t __io_read_fn (void *__cookie, char *__buf, size_t __nbytes);







typedef __ssize_t __io_write_fn (void *__cookie, __const char *__buf,
     size_t __n);







typedef int __io_seek_fn (void *__cookie, __off64_t *__pos, int __w);


typedef int __io_close_fn (void *__cookie);
# 416 "/usr/include/libio.h" 3 4
extern int __underflow (_IO_FILE *);
extern int __uflow (_IO_FILE *);
extern int __overflow (_IO_FILE *, int);
# 460 "/usr/include/libio.h" 3 4
extern int _IO_getc (_IO_FILE *__fp);
extern int _IO_putc (int __c, _IO_FILE *__fp);
extern int _IO_feof (_IO_FILE *__fp) __attribute__ ((__nothrow__));
extern int _IO_ferror (_IO_FILE *__fp) __attribute__ ((__nothrow__));

extern int _IO_peekc_locked (_IO_FILE *__fp);





extern void _IO_flockfile (_IO_FILE *) __attribute__ ((__nothrow__));
extern void _IO_funlockfile (_IO_FILE *) __attribute__ ((__nothrow__));
extern int _IO_ftrylockfile (_IO_FILE *) __attribute__ ((__nothrow__));
# 490 "/usr/include/libio.h" 3 4
extern int _IO_vfscanf (_IO_FILE * __restrict, const char * __restrict,
   __gnuc_va_list, int *__restrict);
extern int _IO_vfprintf (_IO_FILE *__restrict, const char *__restrict,
    __gnuc_va_list);
extern __ssize_t _IO_padn (_IO_FILE *, int, __ssize_t);
extern size_t _IO_sgetn (_IO_FILE *, void *, size_t);

extern __off64_t _IO_seekoff (_IO_FILE *, __off64_t, int, int);
extern __off64_t _IO_seekpos (_IO_FILE *, __off64_t, int);

extern void _IO_free_backup_area (_IO_FILE *) __attribute__ ((__nothrow__));
# 76 "/usr/include/stdio.h" 2 3 4




typedef __gnuc_va_list va_list;
# 109 "/usr/include/stdio.h" 3 4


typedef _G_fpos_t fpos_t;




# 161 "/usr/include/stdio.h" 3 4
# 1 "/usr/include/bits/stdio_lim.h" 1 3 4
# 162 "/usr/include/stdio.h" 2 3 4



extern struct _IO_FILE *stdin;
extern struct _IO_FILE *stdout;
extern struct _IO_FILE *stderr;









extern int remove (__const char *__filename) __attribute__ ((__nothrow__));

extern int rename (__const char *__old, __const char *__new) __attribute__ ((__nothrow__));




extern int renameat (int __oldfd, __const char *__old, int __newfd,
       __const char *__new) __attribute__ ((__nothrow__));








extern FILE *tmpfile (void) ;
# 208 "/usr/include/stdio.h" 3 4
extern char *tmpnam (char *__s) __attribute__ ((__nothrow__)) ;





extern char *tmpnam_r (char *__s) __attribute__ ((__nothrow__)) ;
# 226 "/usr/include/stdio.h" 3 4
extern char *tempnam (__const char *__dir, __const char *__pfx)
     __attribute__ ((__nothrow__)) __attribute__ ((__malloc__)) ;








extern int fclose (FILE *__stream);




extern int fflush (FILE *__stream);

# 251 "/usr/include/stdio.h" 3 4
extern int fflush_unlocked (FILE *__stream);
# 265 "/usr/include/stdio.h" 3 4






extern FILE *fopen (__const char *__restrict __filename,
      __const char *__restrict __modes) ;




extern FILE *freopen (__const char *__restrict __filename,
        __const char *__restrict __modes,
        FILE *__restrict __stream) ;
# 294 "/usr/include/stdio.h" 3 4

# 305 "/usr/include/stdio.h" 3 4
extern FILE *fdopen (int __fd, __const char *__modes) __attribute__ ((__nothrow__)) ;
# 318 "/usr/include/stdio.h" 3 4
extern FILE *fmemopen (void *__s, size_t __len, __const char *__modes)
  __attribute__ ((__nothrow__)) ;




extern FILE *open_memstream (char **__bufloc, size_t *__sizeloc) __attribute__ ((__nothrow__)) ;






extern void setbuf (FILE *__restrict __stream, char *__restrict __buf) __attribute__ ((__nothrow__));



extern int setvbuf (FILE *__restrict __stream, char *__restrict __buf,
      int __modes, size_t __n) __attribute__ ((__nothrow__));





extern void setbuffer (FILE *__restrict __stream, char *__restrict __buf,
         size_t __size) __attribute__ ((__nothrow__));


extern void setlinebuf (FILE *__stream) __attribute__ ((__nothrow__));








extern int fprintf (FILE *__restrict __stream,
      __const char *__restrict __format, ...);




extern int printf (__const char *__restrict __format, ...);

extern int sprintf (char *__restrict __s,
      __const char *__restrict __format, ...) __attribute__ ((__nothrow__));





extern int vfprintf (FILE *__restrict __s, __const char *__restrict __format,
       __gnuc_va_list __arg);




extern int vprintf (__const char *__restrict __format, __gnuc_va_list __arg);

extern int vsprintf (char *__restrict __s, __const char *__restrict __format,
       __gnuc_va_list __arg) __attribute__ ((__nothrow__));





extern int snprintf (char *__restrict __s, size_t __maxlen,
       __const char *__restrict __format, ...)
     __attribute__ ((__nothrow__)) __attribute__ ((__format__ (__printf__, 3, 4)));

extern int vsnprintf (char *__restrict __s, size_t __maxlen,
        __const char *__restrict __format, __gnuc_va_list __arg)
     __attribute__ ((__nothrow__)) __attribute__ ((__format__ (__printf__, 3, 0)));

# 416 "/usr/include/stdio.h" 3 4
extern int vdprintf (int __fd, __const char *__restrict __fmt,
       __gnuc_va_list __arg)
     __attribute__ ((__format__ (__printf__, 2, 0)));
extern int dprintf (int __fd, __const char *__restrict __fmt, ...)
     __attribute__ ((__format__ (__printf__, 2, 3)));








extern int fscanf (FILE *__restrict __stream,
     __const char *__restrict __format, ...) ;




extern int scanf (__const char *__restrict __format, ...) ;

extern int sscanf (__const char *__restrict __s,
     __const char *__restrict __format, ...) __attribute__ ((__nothrow__));
# 447 "/usr/include/stdio.h" 3 4
extern int fscanf (FILE *__restrict __stream, __const char *__restrict __format, ...) __asm__ ("" "__isoc99_fscanf")

                               ;
extern int scanf (__const char *__restrict __format, ...) __asm__ ("" "__isoc99_scanf")
                              ;
extern int sscanf (__const char *__restrict __s, __const char *__restrict __format, ...) __asm__ ("" "__isoc99_sscanf")

                          __attribute__ ((__nothrow__));
# 467 "/usr/include/stdio.h" 3 4








extern int vfscanf (FILE *__restrict __s, __const char *__restrict __format,
      __gnuc_va_list __arg)
     __attribute__ ((__format__ (__scanf__, 2, 0))) ;





extern int vscanf (__const char *__restrict __format, __gnuc_va_list __arg)
     __attribute__ ((__format__ (__scanf__, 1, 0))) ;


extern int vsscanf (__const char *__restrict __s,
      __const char *__restrict __format, __gnuc_va_list __arg)
     __attribute__ ((__nothrow__)) __attribute__ ((__format__ (__scanf__, 2, 0)));
# 498 "/usr/include/stdio.h" 3 4
extern int vfscanf (FILE *__restrict __s, __const char *__restrict __format, __gnuc_va_list __arg) __asm__ ("" "__isoc99_vfscanf")



     __attribute__ ((__format__ (__scanf__, 2, 0))) ;
extern int vscanf (__const char *__restrict __format, __gnuc_va_list __arg) __asm__ ("" "__isoc99_vscanf")

     __attribute__ ((__format__ (__scanf__, 1, 0))) ;
extern int vsscanf (__const char *__restrict __s, __const char *__restrict __format, __gnuc_va_list __arg) __asm__ ("" "__isoc99_vsscanf")



     __attribute__ ((__nothrow__)) __attribute__ ((__format__ (__scanf__, 2, 0)));
# 526 "/usr/include/stdio.h" 3 4









extern int fgetc (FILE *__stream);
extern int getc (FILE *__stream);





extern int getchar (void);

# 554 "/usr/include/stdio.h" 3 4
extern int getc_unlocked (FILE *__stream);
extern int getchar_unlocked (void);
# 565 "/usr/include/stdio.h" 3 4
extern int fgetc_unlocked (FILE *__stream);











extern int fputc (int __c, FILE *__stream);
extern int putc (int __c, FILE *__stream);





extern int putchar (int __c);

# 598 "/usr/include/stdio.h" 3 4
extern int fputc_unlocked (int __c, FILE *__stream);







extern int putc_unlocked (int __c, FILE *__stream);
extern int putchar_unlocked (int __c);






extern int getw (FILE *__stream);


extern int putw (int __w, FILE *__stream);








extern char *fgets (char *__restrict __s, int __n, FILE *__restrict __stream)
     ;






extern char *gets (char *__s) ;

# 660 "/usr/include/stdio.h" 3 4
extern __ssize_t __getdelim (char **__restrict __lineptr,
          size_t *__restrict __n, int __delimiter,
          FILE *__restrict __stream) ;
extern __ssize_t getdelim (char **__restrict __lineptr,
        size_t *__restrict __n, int __delimiter,
        FILE *__restrict __stream) ;







extern __ssize_t getline (char **__restrict __lineptr,
       size_t *__restrict __n,
       FILE *__restrict __stream) ;








extern int fputs (__const char *__restrict __s, FILE *__restrict __stream);





extern int puts (__const char *__s);






extern int ungetc (int __c, FILE *__stream);






extern size_t fread (void *__restrict __ptr, size_t __size,
       size_t __n, FILE *__restrict __stream) ;




extern size_t fwrite (__const void *__restrict __ptr, size_t __size,
        size_t __n, FILE *__restrict __s) ;

# 732 "/usr/include/stdio.h" 3 4
extern size_t fread_unlocked (void *__restrict __ptr, size_t __size,
         size_t __n, FILE *__restrict __stream) ;
extern size_t fwrite_unlocked (__const void *__restrict __ptr, size_t __size,
          size_t __n, FILE *__restrict __stream) ;








extern int fseek (FILE *__stream, long int __off, int __whence);




extern long int ftell (FILE *__stream) ;




extern void rewind (FILE *__stream);

# 768 "/usr/include/stdio.h" 3 4
extern int fseeko (FILE *__stream, __off_t __off, int __whence);




extern __off_t ftello (FILE *__stream) ;
# 787 "/usr/include/stdio.h" 3 4






extern int fgetpos (FILE *__restrict __stream, fpos_t *__restrict __pos);




extern int fsetpos (FILE *__stream, __const fpos_t *__pos);
# 810 "/usr/include/stdio.h" 3 4

# 819 "/usr/include/stdio.h" 3 4


extern void clearerr (FILE *__stream) __attribute__ ((__nothrow__));

extern int feof (FILE *__stream) __attribute__ ((__nothrow__)) ;

extern int ferror (FILE *__stream) __attribute__ ((__nothrow__)) ;




extern void clearerr_unlocked (FILE *__stream) __attribute__ ((__nothrow__));
extern int feof_unlocked (FILE *__stream) __attribute__ ((__nothrow__)) ;
extern int ferror_unlocked (FILE *__stream) __attribute__ ((__nothrow__)) ;








extern void perror (__const char *__s);






# 1 "/usr/include/bits/sys_errlist.h" 1 3 4
# 27 "/usr/include/bits/sys_errlist.h" 3 4
extern int sys_nerr;
extern __const char *__const sys_errlist[];
# 849 "/usr/include/stdio.h" 2 3 4




extern int fileno (FILE *__stream) __attribute__ ((__nothrow__)) ;




extern int fileno_unlocked (FILE *__stream) __attribute__ ((__nothrow__)) ;
# 868 "/usr/include/stdio.h" 3 4
extern FILE *popen (__const char *__command, __const char *__modes) ;





extern int pclose (FILE *__stream);





extern char *ctermid (char *__s) __attribute__ ((__nothrow__));
# 908 "/usr/include/stdio.h" 3 4
extern void flockfile (FILE *__stream) __attribute__ ((__nothrow__));



extern int ftrylockfile (FILE *__stream) __attribute__ ((__nothrow__)) ;


extern void funlockfile (FILE *__stream) __attribute__ ((__nothrow__));
# 938 "/usr/include/stdio.h" 3 4

# 4 "lib/http.c" 2
# 1 "/usr/include/stdlib.h" 1 3 4
# 33 "/usr/include/stdlib.h" 3 4
# 1 "/opt/rh/devtoolset-2/root/usr/lib/gcc/x86_64-redhat-linux/4.8.2/include/stddef.h" 1 3 4
# 324 "/opt/rh/devtoolset-2/root/usr/lib/gcc/x86_64-redhat-linux/4.8.2/include/stddef.h" 3 4
typedef int wchar_t;
# 34 "/usr/include/stdlib.h" 2 3 4








# 1 "/usr/include/bits/waitflags.h" 1 3 4
# 43 "/usr/include/stdlib.h" 2 3 4
# 1 "/usr/include/bits/waitstatus.h" 1 3 4
# 67 "/usr/include/bits/waitstatus.h" 3 4
union wait
  {
    int w_status;
    struct
      {

 unsigned int __w_termsig:7;
 unsigned int __w_coredump:1;
 unsigned int __w_retcode:8;
 unsigned int:16;







      } __wait_terminated;
    struct
      {

 unsigned int __w_stopval:8;
 unsigned int __w_stopsig:8;
 unsigned int:16;






      } __wait_stopped;
  };
# 44 "/usr/include/stdlib.h" 2 3 4
# 68 "/usr/include/stdlib.h" 3 4
typedef union
  {
    union wait *__uptr;
    int *__iptr;
  } __WAIT_STATUS __attribute__ ((__transparent_union__));
# 96 "/usr/include/stdlib.h" 3 4


typedef struct
  {
    int quot;
    int rem;
  } div_t;



typedef struct
  {
    long int quot;
    long int rem;
  } ldiv_t;







__extension__ typedef struct
  {
    long long int quot;
    long long int rem;
  } lldiv_t;


# 140 "/usr/include/stdlib.h" 3 4
extern size_t __ctype_get_mb_cur_max (void) __attribute__ ((__nothrow__)) ;




extern double atof (__const char *__nptr)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1))) ;

extern int atoi (__const char *__nptr)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1))) ;

extern long int atol (__const char *__nptr)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1))) ;





__extension__ extern long long int atoll (__const char *__nptr)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1))) ;





extern double strtod (__const char *__restrict __nptr,
        char **__restrict __endptr)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;





extern float strtof (__const char *__restrict __nptr,
       char **__restrict __endptr) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;

extern long double strtold (__const char *__restrict __nptr,
       char **__restrict __endptr)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;





extern long int strtol (__const char *__restrict __nptr,
   char **__restrict __endptr, int __base)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;

extern unsigned long int strtoul (__const char *__restrict __nptr,
      char **__restrict __endptr, int __base)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;




__extension__
extern long long int strtoq (__const char *__restrict __nptr,
        char **__restrict __endptr, int __base)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;

__extension__
extern unsigned long long int strtouq (__const char *__restrict __nptr,
           char **__restrict __endptr, int __base)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;





__extension__
extern long long int strtoll (__const char *__restrict __nptr,
         char **__restrict __endptr, int __base)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;

__extension__
extern unsigned long long int strtoull (__const char *__restrict __nptr,
     char **__restrict __endptr, int __base)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;

# 311 "/usr/include/stdlib.h" 3 4
extern char *l64a (long int __n) __attribute__ ((__nothrow__)) ;


extern long int a64l (__const char *__s)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1))) ;
# 327 "/usr/include/stdlib.h" 3 4
extern long int random (void) __attribute__ ((__nothrow__));


extern void srandom (unsigned int __seed) __attribute__ ((__nothrow__));





extern char *initstate (unsigned int __seed, char *__statebuf,
   size_t __statelen) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2)));



extern char *setstate (char *__statebuf) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));







struct random_data
  {
    int32_t *fptr;
    int32_t *rptr;
    int32_t *state;
    int rand_type;
    int rand_deg;
    int rand_sep;
    int32_t *end_ptr;
  };

extern int random_r (struct random_data *__restrict __buf,
       int32_t *__restrict __result) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));

extern int srandom_r (unsigned int __seed, struct random_data *__buf)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2)));

extern int initstate_r (unsigned int __seed, char *__restrict __statebuf,
   size_t __statelen,
   struct random_data *__restrict __buf)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2, 4)));

extern int setstate_r (char *__restrict __statebuf,
         struct random_data *__restrict __buf)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));






extern int rand (void) __attribute__ ((__nothrow__));

extern void srand (unsigned int __seed) __attribute__ ((__nothrow__));




extern int rand_r (unsigned int *__seed) __attribute__ ((__nothrow__));







extern double drand48 (void) __attribute__ ((__nothrow__));
extern double erand48 (unsigned short int __xsubi[3]) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));


extern long int lrand48 (void) __attribute__ ((__nothrow__));
extern long int nrand48 (unsigned short int __xsubi[3])
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));


extern long int mrand48 (void) __attribute__ ((__nothrow__));
extern long int jrand48 (unsigned short int __xsubi[3])
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));


extern void srand48 (long int __seedval) __attribute__ ((__nothrow__));
extern unsigned short int *seed48 (unsigned short int __seed16v[3])
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
extern void lcong48 (unsigned short int __param[7]) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));





struct drand48_data
  {
    unsigned short int __x[3];
    unsigned short int __old_x[3];
    unsigned short int __c;
    unsigned short int __init;
    unsigned long long int __a;
  };


extern int drand48_r (struct drand48_data *__restrict __buffer,
        double *__restrict __result) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int erand48_r (unsigned short int __xsubi[3],
        struct drand48_data *__restrict __buffer,
        double *__restrict __result) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));


extern int lrand48_r (struct drand48_data *__restrict __buffer,
        long int *__restrict __result)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int nrand48_r (unsigned short int __xsubi[3],
        struct drand48_data *__restrict __buffer,
        long int *__restrict __result)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));


extern int mrand48_r (struct drand48_data *__restrict __buffer,
        long int *__restrict __result)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern int jrand48_r (unsigned short int __xsubi[3],
        struct drand48_data *__restrict __buffer,
        long int *__restrict __result)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));


extern int srand48_r (long int __seedval, struct drand48_data *__buffer)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2)));

extern int seed48_r (unsigned short int __seed16v[3],
       struct drand48_data *__buffer) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));

extern int lcong48_r (unsigned short int __param[7],
        struct drand48_data *__buffer)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));









extern void *malloc (size_t __size) __attribute__ ((__nothrow__)) __attribute__ ((__malloc__)) ;

extern void *calloc (size_t __nmemb, size_t __size)
     __attribute__ ((__nothrow__)) __attribute__ ((__malloc__)) ;










extern void *realloc (void *__ptr, size_t __size)
     __attribute__ ((__nothrow__)) __attribute__ ((__warn_unused_result__));

extern void free (void *__ptr) __attribute__ ((__nothrow__));




extern void cfree (void *__ptr) __attribute__ ((__nothrow__));



# 1 "/usr/include/alloca.h" 1 3 4
# 25 "/usr/include/alloca.h" 3 4
# 1 "/opt/rh/devtoolset-2/root/usr/lib/gcc/x86_64-redhat-linux/4.8.2/include/stddef.h" 1 3 4
# 26 "/usr/include/alloca.h" 2 3 4







extern void *alloca (size_t __size) __attribute__ ((__nothrow__));






# 498 "/usr/include/stdlib.h" 2 3 4





extern void *valloc (size_t __size) __attribute__ ((__nothrow__)) __attribute__ ((__malloc__)) ;




extern int posix_memalign (void **__memptr, size_t __alignment, size_t __size)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;




extern void abort (void) __attribute__ ((__nothrow__)) __attribute__ ((__noreturn__));



extern int atexit (void (*__func) (void)) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
# 531 "/usr/include/stdlib.h" 3 4





extern int on_exit (void (*__func) (int __status, void *__arg), void *__arg)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));






extern void exit (int __status) __attribute__ ((__nothrow__)) __attribute__ ((__noreturn__));
# 554 "/usr/include/stdlib.h" 3 4






extern void _Exit (int __status) __attribute__ ((__nothrow__)) __attribute__ ((__noreturn__));






extern char *getenv (__const char *__name) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;




extern char *__secure_getenv (__const char *__name)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;





extern int putenv (char *__string) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));





extern int setenv (__const char *__name, __const char *__value, int __replace)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2)));


extern int unsetenv (__const char *__name) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));






extern int clearenv (void) __attribute__ ((__nothrow__));
# 606 "/usr/include/stdlib.h" 3 4
extern char *mktemp (char *__template) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;
# 620 "/usr/include/stdlib.h" 3 4
extern int mkstemp (char *__template) __attribute__ ((__nonnull__ (1))) ;
# 642 "/usr/include/stdlib.h" 3 4
extern int mkstemps (char *__template, int __suffixlen) __attribute__ ((__nonnull__ (1))) ;
# 663 "/usr/include/stdlib.h" 3 4
extern char *mkdtemp (char *__template) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;
# 712 "/usr/include/stdlib.h" 3 4





extern int system (__const char *__command) ;

# 734 "/usr/include/stdlib.h" 3 4
extern char *realpath (__const char *__restrict __name,
         char *__restrict __resolved) __attribute__ ((__nothrow__)) ;






typedef int (*__compar_fn_t) (__const void *, __const void *);
# 752 "/usr/include/stdlib.h" 3 4



extern void *bsearch (__const void *__key, __const void *__base,
        size_t __nmemb, size_t __size, __compar_fn_t __compar)
     __attribute__ ((__nonnull__ (1, 2, 5))) ;



extern void qsort (void *__base, size_t __nmemb, size_t __size,
     __compar_fn_t __compar) __attribute__ ((__nonnull__ (1, 4)));
# 771 "/usr/include/stdlib.h" 3 4
extern int abs (int __x) __attribute__ ((__nothrow__)) __attribute__ ((__const__)) ;
extern long int labs (long int __x) __attribute__ ((__nothrow__)) __attribute__ ((__const__)) ;



__extension__ extern long long int llabs (long long int __x)
     __attribute__ ((__nothrow__)) __attribute__ ((__const__)) ;







extern div_t div (int __numer, int __denom)
     __attribute__ ((__nothrow__)) __attribute__ ((__const__)) ;
extern ldiv_t ldiv (long int __numer, long int __denom)
     __attribute__ ((__nothrow__)) __attribute__ ((__const__)) ;




__extension__ extern lldiv_t lldiv (long long int __numer,
        long long int __denom)
     __attribute__ ((__nothrow__)) __attribute__ ((__const__)) ;

# 808 "/usr/include/stdlib.h" 3 4
extern char *ecvt (double __value, int __ndigit, int *__restrict __decpt,
     int *__restrict __sign) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (3, 4))) ;




extern char *fcvt (double __value, int __ndigit, int *__restrict __decpt,
     int *__restrict __sign) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (3, 4))) ;




extern char *gcvt (double __value, int __ndigit, char *__buf)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (3))) ;




extern char *qecvt (long double __value, int __ndigit,
      int *__restrict __decpt, int *__restrict __sign)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (3, 4))) ;
extern char *qfcvt (long double __value, int __ndigit,
      int *__restrict __decpt, int *__restrict __sign)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (3, 4))) ;
extern char *qgcvt (long double __value, int __ndigit, char *__buf)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (3))) ;




extern int ecvt_r (double __value, int __ndigit, int *__restrict __decpt,
     int *__restrict __sign, char *__restrict __buf,
     size_t __len) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (3, 4, 5)));
extern int fcvt_r (double __value, int __ndigit, int *__restrict __decpt,
     int *__restrict __sign, char *__restrict __buf,
     size_t __len) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (3, 4, 5)));

extern int qecvt_r (long double __value, int __ndigit,
      int *__restrict __decpt, int *__restrict __sign,
      char *__restrict __buf, size_t __len)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (3, 4, 5)));
extern int qfcvt_r (long double __value, int __ndigit,
      int *__restrict __decpt, int *__restrict __sign,
      char *__restrict __buf, size_t __len)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (3, 4, 5)));







extern int mblen (__const char *__s, size_t __n) __attribute__ ((__nothrow__)) ;


extern int mbtowc (wchar_t *__restrict __pwc,
     __const char *__restrict __s, size_t __n) __attribute__ ((__nothrow__)) ;


extern int wctomb (char *__s, wchar_t __wchar) __attribute__ ((__nothrow__)) ;



extern size_t mbstowcs (wchar_t *__restrict __pwcs,
   __const char *__restrict __s, size_t __n) __attribute__ ((__nothrow__));

extern size_t wcstombs (char *__restrict __s,
   __const wchar_t *__restrict __pwcs, size_t __n)
     __attribute__ ((__nothrow__));








extern int rpmatch (__const char *__response) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1))) ;
# 896 "/usr/include/stdlib.h" 3 4
extern int getsubopt (char **__restrict __optionp,
        char *__const *__restrict __tokens,
        char **__restrict __valuep)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2, 3))) ;
# 948 "/usr/include/stdlib.h" 3 4
extern int getloadavg (double __loadavg[], int __nelem)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));
# 964 "/usr/include/stdlib.h" 3 4

# 5 "lib/http.c" 2
# 1 "/usr/include/string.h" 1 3 4
# 29 "/usr/include/string.h" 3 4





# 1 "/opt/rh/devtoolset-2/root/usr/lib/gcc/x86_64-redhat-linux/4.8.2/include/stddef.h" 1 3 4
# 35 "/usr/include/string.h" 2 3 4









extern void *memcpy (void *__restrict __dest,
       __const void *__restrict __src, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));


extern void *memmove (void *__dest, __const void *__src, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));






extern void *memccpy (void *__restrict __dest, __const void *__restrict __src,
        int __c, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));





extern void *memset (void *__s, int __c, size_t __n) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));


extern int memcmp (__const void *__s1, __const void *__s2, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));
# 95 "/usr/include/string.h" 3 4
extern void *memchr (__const void *__s, int __c, size_t __n)
      __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1)));


# 126 "/usr/include/string.h" 3 4


extern char *strcpy (char *__restrict __dest, __const char *__restrict __src)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));

extern char *strncpy (char *__restrict __dest,
        __const char *__restrict __src, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));


extern char *strcat (char *__restrict __dest, __const char *__restrict __src)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));

extern char *strncat (char *__restrict __dest, __const char *__restrict __src,
        size_t __n) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));


extern int strcmp (__const char *__s1, __const char *__s2)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));

extern int strncmp (__const char *__s1, __const char *__s2, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));


extern int strcoll (__const char *__s1, __const char *__s2)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));

extern size_t strxfrm (char *__restrict __dest,
         __const char *__restrict __src, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2)));






# 1 "/usr/include/xlocale.h" 1 3 4
# 28 "/usr/include/xlocale.h" 3 4
typedef struct __locale_struct
{

  struct __locale_data *__locales[13];


  const unsigned short int *__ctype_b;
  const int *__ctype_tolower;
  const int *__ctype_toupper;


  const char *__names[13];
} *__locale_t;


typedef __locale_t locale_t;
# 163 "/usr/include/string.h" 2 3 4


extern int strcoll_l (__const char *__s1, __const char *__s2, __locale_t __l)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2, 3)));

extern size_t strxfrm_l (char *__dest, __const char *__src, size_t __n,
    __locale_t __l) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2, 4)));





extern char *strdup (__const char *__s)
     __attribute__ ((__nothrow__)) __attribute__ ((__malloc__)) __attribute__ ((__nonnull__ (1)));






extern char *strndup (__const char *__string, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__malloc__)) __attribute__ ((__nonnull__ (1)));
# 210 "/usr/include/string.h" 3 4

# 235 "/usr/include/string.h" 3 4
extern char *strchr (__const char *__s, int __c)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1)));
# 262 "/usr/include/string.h" 3 4
extern char *strrchr (__const char *__s, int __c)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1)));


# 281 "/usr/include/string.h" 3 4



extern size_t strcspn (__const char *__s, __const char *__reject)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));


extern size_t strspn (__const char *__s, __const char *__accept)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));
# 314 "/usr/include/string.h" 3 4
extern char *strpbrk (__const char *__s, __const char *__accept)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));
# 342 "/usr/include/string.h" 3 4
extern char *strstr (__const char *__haystack, __const char *__needle)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));




extern char *strtok (char *__restrict __s, __const char *__restrict __delim)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2)));




extern char *__strtok_r (char *__restrict __s,
    __const char *__restrict __delim,
    char **__restrict __save_ptr)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2, 3)));

extern char *strtok_r (char *__restrict __s, __const char *__restrict __delim,
         char **__restrict __save_ptr)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (2, 3)));
# 397 "/usr/include/string.h" 3 4


extern size_t strlen (__const char *__s)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1)));





extern size_t strnlen (__const char *__string, size_t __maxlen)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1)));





extern char *strerror (int __errnum) __attribute__ ((__nothrow__));

# 427 "/usr/include/string.h" 3 4
extern int strerror_r (int __errnum, char *__buf, size_t __buflen) __asm__ ("" "__xpg_strerror_r") __attribute__ ((__nothrow__))

                        __attribute__ ((__nonnull__ (2)));
# 445 "/usr/include/string.h" 3 4
extern char *strerror_l (int __errnum, __locale_t __l) __attribute__ ((__nothrow__));





extern void __bzero (void *__s, size_t __n) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));



extern void bcopy (__const void *__src, void *__dest, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));


extern void bzero (void *__s, size_t __n) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));


extern int bcmp (__const void *__s1, __const void *__s2, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));
# 489 "/usr/include/string.h" 3 4
extern char *index (__const char *__s, int __c)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1)));
# 517 "/usr/include/string.h" 3 4
extern char *rindex (__const char *__s, int __c)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1)));




extern int ffs (int __i) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
# 536 "/usr/include/string.h" 3 4
extern int strcasecmp (__const char *__s1, __const char *__s2)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));


extern int strncasecmp (__const char *__s1, __const char *__s2, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__pure__)) __attribute__ ((__nonnull__ (1, 2)));
# 559 "/usr/include/string.h" 3 4
extern char *strsep (char **__restrict __stringp,
       __const char *__restrict __delim)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));




extern char *strsignal (int __sig) __attribute__ ((__nothrow__));


extern char *__stpcpy (char *__restrict __dest, __const char *__restrict __src)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern char *stpcpy (char *__restrict __dest, __const char *__restrict __src)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));



extern char *__stpncpy (char *__restrict __dest,
   __const char *__restrict __src, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
extern char *stpncpy (char *__restrict __dest,
        __const char *__restrict __src, size_t __n)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1, 2)));
# 646 "/usr/include/string.h" 3 4

# 6 "lib/http.c" 2

# 1 "/opt/rh/devtoolset-2/root/usr/lib/gcc/x86_64-redhat-linux/4.8.2/include/stdarg.h" 1 3 4
# 8 "lib/http.c" 2
# 1 "/usr/include/ctype.h" 1 3 4
# 30 "/usr/include/ctype.h" 3 4

# 48 "/usr/include/ctype.h" 3 4
enum
{
  _ISupper = ((0) < 8 ? ((1 << (0)) << 8) : ((1 << (0)) >> 8)),
  _ISlower = ((1) < 8 ? ((1 << (1)) << 8) : ((1 << (1)) >> 8)),
  _ISalpha = ((2) < 8 ? ((1 << (2)) << 8) : ((1 << (2)) >> 8)),
  _ISdigit = ((3) < 8 ? ((1 << (3)) << 8) : ((1 << (3)) >> 8)),
  _ISxdigit = ((4) < 8 ? ((1 << (4)) << 8) : ((1 << (4)) >> 8)),
  _ISspace = ((5) < 8 ? ((1 << (5)) << 8) : ((1 << (5)) >> 8)),
  _ISprint = ((6) < 8 ? ((1 << (6)) << 8) : ((1 << (6)) >> 8)),
  _ISgraph = ((7) < 8 ? ((1 << (7)) << 8) : ((1 << (7)) >> 8)),
  _ISblank = ((8) < 8 ? ((1 << (8)) << 8) : ((1 << (8)) >> 8)),
  _IScntrl = ((9) < 8 ? ((1 << (9)) << 8) : ((1 << (9)) >> 8)),
  _ISpunct = ((10) < 8 ? ((1 << (10)) << 8) : ((1 << (10)) >> 8)),
  _ISalnum = ((11) < 8 ? ((1 << (11)) << 8) : ((1 << (11)) >> 8))
};
# 81 "/usr/include/ctype.h" 3 4
extern __const unsigned short int **__ctype_b_loc (void)
     __attribute__ ((__nothrow__)) __attribute__ ((__const));
extern __const __int32_t **__ctype_tolower_loc (void)
     __attribute__ ((__nothrow__)) __attribute__ ((__const));
extern __const __int32_t **__ctype_toupper_loc (void)
     __attribute__ ((__nothrow__)) __attribute__ ((__const));
# 96 "/usr/include/ctype.h" 3 4






extern int isalnum (int) __attribute__ ((__nothrow__));
extern int isalpha (int) __attribute__ ((__nothrow__));
extern int iscntrl (int) __attribute__ ((__nothrow__));
extern int isdigit (int) __attribute__ ((__nothrow__));
extern int islower (int) __attribute__ ((__nothrow__));
extern int isgraph (int) __attribute__ ((__nothrow__));
extern int isprint (int) __attribute__ ((__nothrow__));
extern int ispunct (int) __attribute__ ((__nothrow__));
extern int isspace (int) __attribute__ ((__nothrow__));
extern int isupper (int) __attribute__ ((__nothrow__));
extern int isxdigit (int) __attribute__ ((__nothrow__));



extern int tolower (int __c) __attribute__ ((__nothrow__));


extern int toupper (int __c) __attribute__ ((__nothrow__));








extern int isblank (int) __attribute__ ((__nothrow__));


# 142 "/usr/include/ctype.h" 3 4
extern int isascii (int __c) __attribute__ ((__nothrow__));



extern int toascii (int __c) __attribute__ ((__nothrow__));



extern int _toupper (int) __attribute__ ((__nothrow__));
extern int _tolower (int) __attribute__ ((__nothrow__));
# 247 "/usr/include/ctype.h" 3 4
extern int isalnum_l (int, __locale_t) __attribute__ ((__nothrow__));
extern int isalpha_l (int, __locale_t) __attribute__ ((__nothrow__));
extern int iscntrl_l (int, __locale_t) __attribute__ ((__nothrow__));
extern int isdigit_l (int, __locale_t) __attribute__ ((__nothrow__));
extern int islower_l (int, __locale_t) __attribute__ ((__nothrow__));
extern int isgraph_l (int, __locale_t) __attribute__ ((__nothrow__));
extern int isprint_l (int, __locale_t) __attribute__ ((__nothrow__));
extern int ispunct_l (int, __locale_t) __attribute__ ((__nothrow__));
extern int isspace_l (int, __locale_t) __attribute__ ((__nothrow__));
extern int isupper_l (int, __locale_t) __attribute__ ((__nothrow__));
extern int isxdigit_l (int, __locale_t) __attribute__ ((__nothrow__));

extern int isblank_l (int, __locale_t) __attribute__ ((__nothrow__));



extern int __tolower_l (int __c, __locale_t __l) __attribute__ ((__nothrow__));
extern int tolower_l (int __c, __locale_t __l) __attribute__ ((__nothrow__));


extern int __toupper_l (int __c, __locale_t __l) __attribute__ ((__nothrow__));
extern int toupper_l (int __c, __locale_t __l) __attribute__ ((__nothrow__));
# 323 "/usr/include/ctype.h" 3 4

# 9 "lib/http.c" 2


# 1 "/usr/include/sys/un.h" 1 3 4
# 27 "/usr/include/sys/un.h" 3 4



struct sockaddr_un
  {
    sa_family_t sun_family;
    char sun_path[108];
  };
# 45 "/usr/include/sys/un.h" 3 4

# 12 "lib/http.c" 2

# 1 "/usr/include/netinet/tcp.h" 1 3 4
# 92 "/usr/include/netinet/tcp.h" 3 4
struct tcphdr
  {
    u_int16_t source;
    u_int16_t dest;
    u_int32_t seq;
    u_int32_t ack_seq;

    u_int16_t res1:4;
    u_int16_t doff:4;
    u_int16_t fin:1;
    u_int16_t syn:1;
    u_int16_t rst:1;
    u_int16_t psh:1;
    u_int16_t ack:1;
    u_int16_t urg:1;
    u_int16_t res2:2;
# 121 "/usr/include/netinet/tcp.h" 3 4
    u_int16_t window;
    u_int16_t check;
    u_int16_t urg_ptr;
};


enum
{
  TCP_ESTABLISHED = 1,
  TCP_SYN_SENT,
  TCP_SYN_RECV,
  TCP_FIN_WAIT1,
  TCP_FIN_WAIT2,
  TCP_TIME_WAIT,
  TCP_CLOSE,
  TCP_CLOSE_WAIT,
  TCP_LAST_ACK,
  TCP_LISTEN,
  TCP_CLOSING
};
# 179 "/usr/include/netinet/tcp.h" 3 4
enum tcp_ca_state
{
  TCP_CA_Open = 0,
  TCP_CA_Disorder = 1,
  TCP_CA_CWR = 2,
  TCP_CA_Recovery = 3,
  TCP_CA_Loss = 4
};

struct tcp_info
{
  u_int8_t tcpi_state;
  u_int8_t tcpi_ca_state;
  u_int8_t tcpi_retransmits;
  u_int8_t tcpi_probes;
  u_int8_t tcpi_backoff;
  u_int8_t tcpi_options;
  u_int8_t tcpi_snd_wscale : 4, tcpi_rcv_wscale : 4;

  u_int32_t tcpi_rto;
  u_int32_t tcpi_ato;
  u_int32_t tcpi_snd_mss;
  u_int32_t tcpi_rcv_mss;

  u_int32_t tcpi_unacked;
  u_int32_t tcpi_sacked;
  u_int32_t tcpi_lost;
  u_int32_t tcpi_retrans;
  u_int32_t tcpi_fackets;


  u_int32_t tcpi_last_data_sent;
  u_int32_t tcpi_last_ack_sent;
  u_int32_t tcpi_last_data_recv;
  u_int32_t tcpi_last_ack_recv;


  u_int32_t tcpi_pmtu;
  u_int32_t tcpi_rcv_ssthresh;
  u_int32_t tcpi_rtt;
  u_int32_t tcpi_rttvar;
  u_int32_t tcpi_snd_ssthresh;
  u_int32_t tcpi_snd_cwnd;
  u_int32_t tcpi_advmss;
  u_int32_t tcpi_reordering;

  u_int32_t tcpi_rcv_rtt;
  u_int32_t tcpi_rcv_space;

  u_int32_t tcpi_total_retrans;
};





struct tcp_md5sig
{
  struct sockaddr_storage tcpm_addr;
  u_int16_t __tcpm_pad1;
  u_int16_t tcpm_keylen;
  u_int32_t __tcpm_pad2;
  u_int8_t tcpm_key[80];
};
# 14 "lib/http.c" 2
# 1 "/usr/include/errno.h" 1 3 4
# 32 "/usr/include/errno.h" 3 4




# 1 "/usr/include/bits/errno.h" 1 3 4
# 25 "/usr/include/bits/errno.h" 3 4
# 1 "/usr/include/linux/errno.h" 1 3 4



# 1 "/usr/include/asm/errno.h" 1 3 4
# 1 "/usr/include/asm-generic/errno.h" 1 3 4



# 1 "/usr/include/asm-generic/errno-base.h" 1 3 4
# 5 "/usr/include/asm-generic/errno.h" 2 3 4
# 1 "/usr/include/asm/errno.h" 2 3 4
# 5 "/usr/include/linux/errno.h" 2 3 4
# 26 "/usr/include/bits/errno.h" 2 3 4
# 47 "/usr/include/bits/errno.h" 3 4
extern int *__errno_location (void) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
# 37 "/usr/include/errno.h" 2 3 4
# 59 "/usr/include/errno.h" 3 4

# 15 "lib/http.c" 2

# 1 "/usr/include/arpa/inet.h" 1 3 4
# 31 "/usr/include/arpa/inet.h" 3 4




extern in_addr_t inet_addr (__const char *__cp) __attribute__ ((__nothrow__));


extern in_addr_t inet_lnaof (struct in_addr __in) __attribute__ ((__nothrow__));



extern struct in_addr inet_makeaddr (in_addr_t __net, in_addr_t __host)
     __attribute__ ((__nothrow__));


extern in_addr_t inet_netof (struct in_addr __in) __attribute__ ((__nothrow__));



extern in_addr_t inet_network (__const char *__cp) __attribute__ ((__nothrow__));



extern char *inet_ntoa (struct in_addr __in) __attribute__ ((__nothrow__));




extern int inet_pton (int __af, __const char *__restrict __cp,
        void *__restrict __buf) __attribute__ ((__nothrow__));




extern __const char *inet_ntop (int __af, __const void *__restrict __cp,
    char *__restrict __buf, socklen_t __len)
     __attribute__ ((__nothrow__));






extern int inet_aton (__const char *__cp, struct in_addr *__inp) __attribute__ ((__nothrow__));



extern char *inet_neta (in_addr_t __net, char *__buf, size_t __len) __attribute__ ((__nothrow__));




extern char *inet_net_ntop (int __af, __const void *__cp, int __bits,
       char *__buf, size_t __len) __attribute__ ((__nothrow__));




extern int inet_net_pton (int __af, __const char *__cp,
     void *__buf, size_t __len) __attribute__ ((__nothrow__));




extern unsigned int inet_nsap_addr (__const char *__cp,
        unsigned char *__buf, int __len) __attribute__ ((__nothrow__));



extern char *inet_nsap_ntoa (int __len, __const unsigned char *__cp,
        char *__buf) __attribute__ ((__nothrow__));



# 17 "lib/http.c" 2
# 1 "/usr/include/netdb.h" 1 3 4
# 33 "/usr/include/netdb.h" 3 4
# 1 "/usr/include/rpc/netdb.h" 1 3 4
# 42 "/usr/include/rpc/netdb.h" 3 4
# 1 "/opt/rh/devtoolset-2/root/usr/lib/gcc/x86_64-redhat-linux/4.8.2/include/stddef.h" 1 3 4
# 43 "/usr/include/rpc/netdb.h" 2 3 4



struct rpcent
{
  char *r_name;
  char **r_aliases;
  int r_number;
};

extern void setrpcent (int __stayopen) __attribute__ ((__nothrow__));
extern void endrpcent (void) __attribute__ ((__nothrow__));
extern struct rpcent *getrpcbyname (__const char *__name) __attribute__ ((__nothrow__));
extern struct rpcent *getrpcbynumber (int __number) __attribute__ ((__nothrow__));
extern struct rpcent *getrpcent (void) __attribute__ ((__nothrow__));


extern int getrpcbyname_r (__const char *__name, struct rpcent *__result_buf,
      char *__buffer, size_t __buflen,
      struct rpcent **__result) __attribute__ ((__nothrow__));

extern int getrpcbynumber_r (int __number, struct rpcent *__result_buf,
        char *__buffer, size_t __buflen,
        struct rpcent **__result) __attribute__ ((__nothrow__));

extern int getrpcent_r (struct rpcent *__result_buf, char *__buffer,
   size_t __buflen, struct rpcent **__result) __attribute__ ((__nothrow__));



# 34 "/usr/include/netdb.h" 2 3 4
# 43 "/usr/include/netdb.h" 3 4
# 1 "/usr/include/bits/netdb.h" 1 3 4
# 27 "/usr/include/bits/netdb.h" 3 4
struct netent
{
  char *n_name;
  char **n_aliases;
  int n_addrtype;
  uint32_t n_net;
};
# 44 "/usr/include/netdb.h" 2 3 4
# 54 "/usr/include/netdb.h" 3 4








extern int *__h_errno_location (void) __attribute__ ((__nothrow__)) __attribute__ ((__const__));
# 93 "/usr/include/netdb.h" 3 4
extern void herror (__const char *__str) __attribute__ ((__nothrow__));


extern __const char *hstrerror (int __err_num) __attribute__ ((__nothrow__));




struct hostent
{
  char *h_name;
  char **h_aliases;
  int h_addrtype;
  int h_length;
  char **h_addr_list;



};






extern void sethostent (int __stay_open);





extern void endhostent (void);






extern struct hostent *gethostent (void);






extern struct hostent *gethostbyaddr (__const void *__addr, __socklen_t __len,
          int __type);





extern struct hostent *gethostbyname (__const char *__name);
# 156 "/usr/include/netdb.h" 3 4
extern struct hostent *gethostbyname2 (__const char *__name, int __af);
# 168 "/usr/include/netdb.h" 3 4
extern int gethostent_r (struct hostent *__restrict __result_buf,
    char *__restrict __buf, size_t __buflen,
    struct hostent **__restrict __result,
    int *__restrict __h_errnop);

extern int gethostbyaddr_r (__const void *__restrict __addr, __socklen_t __len,
       int __type,
       struct hostent *__restrict __result_buf,
       char *__restrict __buf, size_t __buflen,
       struct hostent **__restrict __result,
       int *__restrict __h_errnop);

extern int gethostbyname_r (__const char *__restrict __name,
       struct hostent *__restrict __result_buf,
       char *__restrict __buf, size_t __buflen,
       struct hostent **__restrict __result,
       int *__restrict __h_errnop);

extern int gethostbyname2_r (__const char *__restrict __name, int __af,
        struct hostent *__restrict __result_buf,
        char *__restrict __buf, size_t __buflen,
        struct hostent **__restrict __result,
        int *__restrict __h_errnop);
# 199 "/usr/include/netdb.h" 3 4
extern void setnetent (int __stay_open);





extern void endnetent (void);






extern struct netent *getnetent (void);






extern struct netent *getnetbyaddr (uint32_t __net, int __type);





extern struct netent *getnetbyname (__const char *__name);
# 238 "/usr/include/netdb.h" 3 4
extern int getnetent_r (struct netent *__restrict __result_buf,
   char *__restrict __buf, size_t __buflen,
   struct netent **__restrict __result,
   int *__restrict __h_errnop);

extern int getnetbyaddr_r (uint32_t __net, int __type,
      struct netent *__restrict __result_buf,
      char *__restrict __buf, size_t __buflen,
      struct netent **__restrict __result,
      int *__restrict __h_errnop);

extern int getnetbyname_r (__const char *__restrict __name,
      struct netent *__restrict __result_buf,
      char *__restrict __buf, size_t __buflen,
      struct netent **__restrict __result,
      int *__restrict __h_errnop);




struct servent
{
  char *s_name;
  char **s_aliases;
  int s_port;
  char *s_proto;
};






extern void setservent (int __stay_open);





extern void endservent (void);






extern struct servent *getservent (void);






extern struct servent *getservbyname (__const char *__name,
          __const char *__proto);






extern struct servent *getservbyport (int __port, __const char *__proto);
# 310 "/usr/include/netdb.h" 3 4
extern int getservent_r (struct servent *__restrict __result_buf,
    char *__restrict __buf, size_t __buflen,
    struct servent **__restrict __result);

extern int getservbyname_r (__const char *__restrict __name,
       __const char *__restrict __proto,
       struct servent *__restrict __result_buf,
       char *__restrict __buf, size_t __buflen,
       struct servent **__restrict __result);

extern int getservbyport_r (int __port, __const char *__restrict __proto,
       struct servent *__restrict __result_buf,
       char *__restrict __buf, size_t __buflen,
       struct servent **__restrict __result);




struct protoent
{
  char *p_name;
  char **p_aliases;
  int p_proto;
};






extern void setprotoent (int __stay_open);





extern void endprotoent (void);






extern struct protoent *getprotoent (void);





extern struct protoent *getprotobyname (__const char *__name);





extern struct protoent *getprotobynumber (int __proto);
# 376 "/usr/include/netdb.h" 3 4
extern int getprotoent_r (struct protoent *__restrict __result_buf,
     char *__restrict __buf, size_t __buflen,
     struct protoent **__restrict __result);

extern int getprotobyname_r (__const char *__restrict __name,
        struct protoent *__restrict __result_buf,
        char *__restrict __buf, size_t __buflen,
        struct protoent **__restrict __result);

extern int getprotobynumber_r (int __proto,
          struct protoent *__restrict __result_buf,
          char *__restrict __buf, size_t __buflen,
          struct protoent **__restrict __result);
# 397 "/usr/include/netdb.h" 3 4
extern int setnetgrent (__const char *__netgroup);







extern void endnetgrent (void);
# 414 "/usr/include/netdb.h" 3 4
extern int getnetgrent (char **__restrict __hostp,
   char **__restrict __userp,
   char **__restrict __domainp);
# 425 "/usr/include/netdb.h" 3 4
extern int innetgr (__const char *__netgroup, __const char *__host,
      __const char *__user, __const char *__domain);







extern int getnetgrent_r (char **__restrict __hostp,
     char **__restrict __userp,
     char **__restrict __domainp,
     char *__restrict __buffer, size_t __buflen);
# 453 "/usr/include/netdb.h" 3 4
extern int rcmd (char **__restrict __ahost, unsigned short int __rport,
   __const char *__restrict __locuser,
   __const char *__restrict __remuser,
   __const char *__restrict __cmd, int *__restrict __fd2p);
# 465 "/usr/include/netdb.h" 3 4
extern int rcmd_af (char **__restrict __ahost, unsigned short int __rport,
      __const char *__restrict __locuser,
      __const char *__restrict __remuser,
      __const char *__restrict __cmd, int *__restrict __fd2p,
      sa_family_t __af);
# 481 "/usr/include/netdb.h" 3 4
extern int rexec (char **__restrict __ahost, int __rport,
    __const char *__restrict __name,
    __const char *__restrict __pass,
    __const char *__restrict __cmd, int *__restrict __fd2p);
# 493 "/usr/include/netdb.h" 3 4
extern int rexec_af (char **__restrict __ahost, int __rport,
       __const char *__restrict __name,
       __const char *__restrict __pass,
       __const char *__restrict __cmd, int *__restrict __fd2p,
       sa_family_t __af);
# 507 "/usr/include/netdb.h" 3 4
extern int ruserok (__const char *__rhost, int __suser,
      __const char *__remuser, __const char *__locuser);
# 517 "/usr/include/netdb.h" 3 4
extern int ruserok_af (__const char *__rhost, int __suser,
         __const char *__remuser, __const char *__locuser,
         sa_family_t __af);
# 530 "/usr/include/netdb.h" 3 4
extern int iruserok (uint32_t __raddr, int __suser,
       __const char *__remuser, __const char *__locuser);
# 541 "/usr/include/netdb.h" 3 4
extern int iruserok_af (__const void *__raddr, int __suser,
   __const char *__remuser, __const char *__locuser,
   sa_family_t __af);
# 553 "/usr/include/netdb.h" 3 4
extern int rresvport (int *__alport);
# 562 "/usr/include/netdb.h" 3 4
extern int rresvport_af (int *__alport, sa_family_t __af);






struct addrinfo
{
  int ai_flags;
  int ai_family;
  int ai_socktype;
  int ai_protocol;
  socklen_t ai_addrlen;
  struct sockaddr *ai_addr;
  char *ai_canonname;
  struct addrinfo *ai_next;
};
# 664 "/usr/include/netdb.h" 3 4
extern int getaddrinfo (__const char *__restrict __name,
   __const char *__restrict __service,
   __const struct addrinfo *__restrict __req,
   struct addrinfo **__restrict __pai);


extern void freeaddrinfo (struct addrinfo *__ai) __attribute__ ((__nothrow__));


extern __const char *gai_strerror (int __ecode) __attribute__ ((__nothrow__));





extern int getnameinfo (__const struct sockaddr *__restrict __sa,
   socklen_t __salen, char *__restrict __host,
   socklen_t __hostlen, char *__restrict __serv,
   socklen_t __servlen, unsigned int __flags);
# 715 "/usr/include/netdb.h" 3 4

# 18 "lib/http.c" 2

# 1 "/usr/include/arpa/nameser.h" 1 3 4
# 59 "/usr/include/arpa/nameser.h" 3 4
# 1 "/usr/include/sys/param.h" 1 3 4
# 26 "/usr/include/sys/param.h" 3 4
# 1 "/opt/rh/devtoolset-2/root/usr/lib/gcc/x86_64-redhat-linux/4.8.2/include/limits.h" 1 3 4
# 34 "/opt/rh/devtoolset-2/root/usr/lib/gcc/x86_64-redhat-linux/4.8.2/include/limits.h" 3 4
# 1 "/opt/rh/devtoolset-2/root/usr/lib/gcc/x86_64-redhat-linux/4.8.2/include/syslimits.h" 1 3 4






# 1 "/opt/rh/devtoolset-2/root/usr/lib/gcc/x86_64-redhat-linux/4.8.2/include/limits.h" 1 3 4
# 168 "/opt/rh/devtoolset-2/root/usr/lib/gcc/x86_64-redhat-linux/4.8.2/include/limits.h" 3 4
# 1 "/usr/include/limits.h" 1 3 4
# 145 "/usr/include/limits.h" 3 4
# 1 "/usr/include/bits/posix1_lim.h" 1 3 4
# 157 "/usr/include/bits/posix1_lim.h" 3 4
# 1 "/usr/include/bits/local_lim.h" 1 3 4
# 39 "/usr/include/bits/local_lim.h" 3 4
# 1 "/usr/include/linux/limits.h" 1 3 4
# 40 "/usr/include/bits/local_lim.h" 2 3 4
# 158 "/usr/include/bits/posix1_lim.h" 2 3 4
# 146 "/usr/include/limits.h" 2 3 4



# 1 "/usr/include/bits/posix2_lim.h" 1 3 4
# 150 "/usr/include/limits.h" 2 3 4
# 169 "/opt/rh/devtoolset-2/root/usr/lib/gcc/x86_64-redhat-linux/4.8.2/include/limits.h" 2 3 4
# 8 "/opt/rh/devtoolset-2/root/usr/lib/gcc/x86_64-redhat-linux/4.8.2/include/syslimits.h" 2 3 4
# 35 "/opt/rh/devtoolset-2/root/usr/lib/gcc/x86_64-redhat-linux/4.8.2/include/limits.h" 2 3 4
# 27 "/usr/include/sys/param.h" 2 3 4

# 1 "/usr/include/linux/param.h" 1 3 4



# 1 "/usr/include/asm/param.h" 1 3 4
# 1 "/usr/include/asm-generic/param.h" 1 3 4
# 1 "/usr/include/asm/param.h" 2 3 4
# 5 "/usr/include/linux/param.h" 2 3 4
# 29 "/usr/include/sys/param.h" 2 3 4
# 60 "/usr/include/arpa/nameser.h" 2 3 4

# 1 "/usr/include/sys/bitypes.h" 1 3 4
# 62 "/usr/include/arpa/nameser.h" 2 3 4
# 98 "/usr/include/arpa/nameser.h" 3 4
typedef enum __ns_sect {
 ns_s_qd = 0,
 ns_s_zn = 0,
 ns_s_an = 1,
 ns_s_pr = 1,
 ns_s_ns = 2,
 ns_s_ud = 2,
 ns_s_ar = 3,
 ns_s_max = 4
} ns_sect;






typedef struct __ns_msg {
 const u_char *_msg, *_eom;
 u_int16_t _id, _flags, _counts[ns_s_max];
 const u_char *_sections[ns_s_max];
 ns_sect _sect;
 int _rrnum;
 const u_char *_msg_ptr;
} ns_msg;


struct _ns_flagdata { int mask, shift; };
extern const struct _ns_flagdata _ns_flagdata[];
# 138 "/usr/include/arpa/nameser.h" 3 4
typedef struct __ns_rr {
 char name[1025];
 u_int16_t type;
 u_int16_t rr_class;
 u_int32_t ttl;
 u_int16_t rdlength;
 const u_char * rdata;
} ns_rr;
# 160 "/usr/include/arpa/nameser.h" 3 4
typedef enum __ns_flag {
 ns_f_qr,
 ns_f_opcode,
 ns_f_aa,
 ns_f_tc,
 ns_f_rd,
 ns_f_ra,
 ns_f_z,
 ns_f_ad,
 ns_f_cd,
 ns_f_rcode,
 ns_f_max
} ns_flag;




typedef enum __ns_opcode {
 ns_o_query = 0,
 ns_o_iquery = 1,
 ns_o_status = 2,

 ns_o_notify = 4,
 ns_o_update = 5,
 ns_o_max = 6
} ns_opcode;




typedef enum __ns_rcode {
 ns_r_noerror = 0,
 ns_r_formerr = 1,
 ns_r_servfail = 2,
 ns_r_nxdomain = 3,
 ns_r_notimpl = 4,
 ns_r_refused = 5,

 ns_r_yxdomain = 6,
 ns_r_yxrrset = 7,
 ns_r_nxrrset = 8,
 ns_r_notauth = 9,
 ns_r_notzone = 10,
 ns_r_max = 11,

 ns_r_badvers = 16,

 ns_r_badsig = 16,
 ns_r_badkey = 17,
 ns_r_badtime = 18
} ns_rcode;


typedef enum __ns_update_operation {
 ns_uop_delete = 0,
 ns_uop_add = 1,
 ns_uop_max = 2
} ns_update_operation;




struct ns_tsig_key {
        char name[1025], alg[1025];
        unsigned char *data;
        int len;
};
typedef struct ns_tsig_key ns_tsig_key;




struct ns_tcp_tsig_state {
 int counter;
 struct dst_key *key;
 void *ctx;
 unsigned char sig[512];
 int siglen;
};
typedef struct ns_tcp_tsig_state ns_tcp_tsig_state;
# 252 "/usr/include/arpa/nameser.h" 3 4
typedef enum __ns_type {
 ns_t_invalid = 0,
 ns_t_a = 1,
 ns_t_ns = 2,
 ns_t_md = 3,
 ns_t_mf = 4,
 ns_t_cname = 5,
 ns_t_soa = 6,
 ns_t_mb = 7,
 ns_t_mg = 8,
 ns_t_mr = 9,
 ns_t_null = 10,
 ns_t_wks = 11,
 ns_t_ptr = 12,
 ns_t_hinfo = 13,
 ns_t_minfo = 14,
 ns_t_mx = 15,
 ns_t_txt = 16,
 ns_t_rp = 17,
 ns_t_afsdb = 18,
 ns_t_x25 = 19,
 ns_t_isdn = 20,
 ns_t_rt = 21,
 ns_t_nsap = 22,
 ns_t_nsap_ptr = 23,
 ns_t_sig = 24,
 ns_t_key = 25,
 ns_t_px = 26,
 ns_t_gpos = 27,
 ns_t_aaaa = 28,
 ns_t_loc = 29,
 ns_t_nxt = 30,
 ns_t_eid = 31,
 ns_t_nimloc = 32,
 ns_t_srv = 33,
 ns_t_atma = 34,
 ns_t_naptr = 35,
 ns_t_kx = 36,
 ns_t_cert = 37,
 ns_t_a6 = 38,
 ns_t_dname = 39,
 ns_t_sink = 40,
 ns_t_opt = 41,
 ns_t_apl = 42,
 ns_t_rrsig = 46,
 ns_t_nsec = 47,
 ns_t_dnskey = 48,
 ns_t_tkey = 249,
 ns_t_tsig = 250,
 ns_t_ixfr = 251,
 ns_t_axfr = 252,
 ns_t_mailb = 253,
 ns_t_maila = 254,
 ns_t_any = 255,
 ns_t_zxfr = 256,
 ns_t_max = 65536
} ns_type;
# 324 "/usr/include/arpa/nameser.h" 3 4
typedef enum __ns_class {
 ns_c_invalid = 0,
 ns_c_in = 1,
 ns_c_2 = 2,
 ns_c_chaos = 3,
 ns_c_hs = 4,

 ns_c_none = 254,
 ns_c_any = 255,
 ns_c_max = 65536
} ns_class;



typedef enum __ns_key_types {
 ns_kt_rsa = 1,
 ns_kt_dh = 2,
 ns_kt_dsa = 3,
 ns_kt_private = 254
} ns_key_types;

typedef enum __ns_cert_types {
 cert_t_pkix = 1,
 cert_t_spki = 2,
 cert_t_pgp = 3,
 cert_t_url = 253,
 cert_t_oid = 254
} ns_cert_types;
# 474 "/usr/include/arpa/nameser.h" 3 4

int ns_msg_getflag (ns_msg, int) __attribute__ ((__nothrow__));
u_int ns_get16 (const u_char *) __attribute__ ((__nothrow__));
u_long ns_get32 (const u_char *) __attribute__ ((__nothrow__));
void ns_put16 (u_int, u_char *) __attribute__ ((__nothrow__));
void ns_put32 (u_long, u_char *) __attribute__ ((__nothrow__));
int ns_initparse (const u_char *, int, ns_msg *) __attribute__ ((__nothrow__));
int ns_skiprr (const u_char *, const u_char *, ns_sect, int)
     __attribute__ ((__nothrow__));
int ns_parserr (ns_msg *, ns_sect, int, ns_rr *) __attribute__ ((__nothrow__));
int ns_sprintrr (const ns_msg *, const ns_rr *,
        const char *, const char *, char *, size_t)
     __attribute__ ((__nothrow__));
int ns_sprintrrf (const u_char *, size_t, const char *,
         ns_class, ns_type, u_long, const u_char *,
         size_t, const char *, const char *,
         char *, size_t) __attribute__ ((__nothrow__));
int ns_format_ttl (u_long, char *, size_t) __attribute__ ((__nothrow__));
int ns_parse_ttl (const char *, u_long *) __attribute__ ((__nothrow__));
u_int32_t ns_datetosecs (const char *, int *) __attribute__ ((__nothrow__));
int ns_name_ntol (const u_char *, u_char *, size_t) __attribute__ ((__nothrow__));
int ns_name_ntop (const u_char *, char *, size_t) __attribute__ ((__nothrow__));
int ns_name_pton (const char *, u_char *, size_t) __attribute__ ((__nothrow__));
int ns_name_unpack (const u_char *, const u_char *,
    const u_char *, u_char *, size_t) __attribute__ ((__nothrow__));
int ns_name_pack (const u_char *, u_char *, int,
         const u_char **, const u_char **) __attribute__ ((__nothrow__));
int ns_name_uncompress (const u_char *, const u_char *,
        const u_char *, char *, size_t) __attribute__ ((__nothrow__));
int ns_name_compress (const char *, u_char *, size_t,
      const u_char **, const u_char **) __attribute__ ((__nothrow__));
int ns_name_skip (const u_char **, const u_char *) __attribute__ ((__nothrow__));
void ns_name_rollback (const u_char *, const u_char **,
      const u_char **) __attribute__ ((__nothrow__));
int ns_sign (u_char *, int *, int, int, void *,
    const u_char *, int, u_char *, int *, time_t) __attribute__ ((__nothrow__));
int ns_sign2 (u_char *, int *, int, int, void *,
     const u_char *, int, u_char *, int *, time_t,
     u_char **, u_char **) __attribute__ ((__nothrow__));
int ns_sign_tcp (u_char *, int *, int, int,
        ns_tcp_tsig_state *, int) __attribute__ ((__nothrow__));
int ns_sign_tcp2 (u_char *, int *, int, int,
         ns_tcp_tsig_state *, int,
         u_char **, u_char **) __attribute__ ((__nothrow__));
int ns_sign_tcp_init (void *, const u_char *, int,
      ns_tcp_tsig_state *) __attribute__ ((__nothrow__));
u_char *ns_find_tsig (u_char *, u_char *) __attribute__ ((__nothrow__));
int ns_verify (u_char *, int *, void *, const u_char *, int,
      u_char *, int *, time_t *, int) __attribute__ ((__nothrow__));
int ns_verify_tcp (u_char *, int *, ns_tcp_tsig_state *, int)
     __attribute__ ((__nothrow__));
int ns_verify_tcp_init (void *, const u_char *, int,
        ns_tcp_tsig_state *) __attribute__ ((__nothrow__));
int ns_samedomain (const char *, const char *) __attribute__ ((__nothrow__));
int ns_subdomain (const char *, const char *) __attribute__ ((__nothrow__));
int ns_makecanon (const char *, char *, size_t) __attribute__ ((__nothrow__));
int ns_samename (const char *, const char *) __attribute__ ((__nothrow__));



# 1 "/usr/include/arpa/nameser_compat.h" 1 3 4
# 48 "/usr/include/arpa/nameser_compat.h" 3 4
typedef struct {
 unsigned id :16;
# 66 "/usr/include/arpa/nameser_compat.h" 3 4
 unsigned rd :1;
 unsigned tc :1;
 unsigned aa :1;
 unsigned opcode :4;
 unsigned qr :1;

 unsigned rcode :4;
 unsigned cd: 1;
 unsigned ad: 1;
 unsigned unused :1;
 unsigned ra :1;


 unsigned qdcount :16;
 unsigned ancount :16;
 unsigned nscount :16;
 unsigned arcount :16;
} HEADER;
# 535 "/usr/include/arpa/nameser.h" 2 3 4
# 20 "lib/http.c" 2
# 1 "/usr/include/resolv.h" 1 3 4
# 71 "/usr/include/resolv.h" 3 4
typedef enum { res_goahead, res_nextns, res_modified, res_done, res_error }
 res_sendhookact;

typedef res_sendhookact (*res_send_qhook) (struct sockaddr_in * const *__ns,
        const u_char **__query,
        int *__querylen,
        u_char *__ans,
        int __anssiz,
        int *__resplen);

typedef res_sendhookact (*res_send_rhook) (const struct sockaddr_in *__ns,
        const u_char *__query,
        int __querylen,
        u_char *__ans,
        int __anssiz,
        int *__resplen);
# 104 "/usr/include/resolv.h" 3 4
struct __res_state {
 int retrans;
 int retry;
 u_long options;
 int nscount;
 struct sockaddr_in
  nsaddr_list[3];

 u_short id;

 char *dnsrch[6 +1];
 char defdname[256];
 u_long pfcode;
 unsigned ndots:4;
 unsigned nsort:4;
 unsigned ipv6_unavail:1;
 unsigned unused:23;
 struct {
  struct in_addr addr;
  u_int32_t mask;
 } sort_list[10];

 res_send_qhook qhook;
 res_send_rhook rhook;
 int res_h_errno;
 int _vcsock;
 u_int _flags;

 union {
  char pad[52];
  struct {
   u_int16_t nscount;
   u_int16_t nsmap[3];
   int nssocks[3];
   u_int16_t nscount6;
   u_int16_t nsinit;
   struct sockaddr_in6 *nsaddrs[3];




   unsigned int _initstamp[2];

  } _ext;
 } _u;
};

typedef struct __res_state *res_state;
# 176 "/usr/include/resolv.h" 3 4
struct res_sym {
 int number;
 char * name;
 char * humanname;
};
# 246 "/usr/include/resolv.h" 3 4

extern struct __res_state *__res_state(void) __attribute__ ((__const__));

# 265 "/usr/include/resolv.h" 3 4

void __fp_nquery (const u_char *, int, FILE *) __attribute__ ((__nothrow__));
void __fp_query (const u_char *, FILE *) __attribute__ ((__nothrow__));
const char * __hostalias (const char *) __attribute__ ((__nothrow__));
void __p_query (const u_char *) __attribute__ ((__nothrow__));
void __res_close (void) __attribute__ ((__nothrow__));
int __res_init (void) __attribute__ ((__nothrow__));
int __res_isourserver (const struct sockaddr_in *) __attribute__ ((__nothrow__));
int __res_mkquery (int, const char *, int, int, const u_char *,
        int, const u_char *, u_char *, int) __attribute__ ((__nothrow__));
int __res_query (const char *, int, int, u_char *, int) __attribute__ ((__nothrow__));
int __res_querydomain (const char *, const char *, int, int,
     u_char *, int) __attribute__ ((__nothrow__));
int __res_search (const char *, int, int, u_char *, int) __attribute__ ((__nothrow__));
int __res_send (const u_char *, int, u_char *, int) __attribute__ ((__nothrow__));

# 325 "/usr/include/resolv.h" 3 4

int __res_hnok (const char *) __attribute__ ((__nothrow__));
int __res_ownok (const char *) __attribute__ ((__nothrow__));
int __res_mailok (const char *) __attribute__ ((__nothrow__));
int __res_dnok (const char *) __attribute__ ((__nothrow__));
int __sym_ston (const struct res_sym *, const char *, int *) __attribute__ ((__nothrow__));
const char * __sym_ntos (const struct res_sym *, int, int *) __attribute__ ((__nothrow__));
const char * __sym_ntop (const struct res_sym *, int, int *) __attribute__ ((__nothrow__));
int __b64_ntop (u_char const *, size_t, char *, size_t) __attribute__ ((__nothrow__));
int __b64_pton (char const *, u_char *, size_t) __attribute__ ((__nothrow__));
int __loc_aton (const char *__ascii, u_char *__binary) __attribute__ ((__nothrow__));
const char * __loc_ntoa (const u_char *__binary, char *__ascii) __attribute__ ((__nothrow__));
int __dn_skipname (const u_char *, const u_char *) __attribute__ ((__nothrow__));
void __putlong (u_int32_t, u_char *) __attribute__ ((__nothrow__));
void __putshort (u_int16_t, u_char *) __attribute__ ((__nothrow__));
const char * __p_class (int) __attribute__ ((__nothrow__));
const char * __p_time (u_int32_t) __attribute__ ((__nothrow__));
const char * __p_type (int) __attribute__ ((__nothrow__));
const char * __p_rcode (int) __attribute__ ((__nothrow__));
const u_char * __p_cdnname (const u_char *, const u_char *, int, FILE *)
     __attribute__ ((__nothrow__));
const u_char * __p_cdname (const u_char *, const u_char *, FILE *) __attribute__ ((__nothrow__));
const u_char * __p_fqnname (const u_char *__cp, const u_char *__msg,
      int, char *, int) __attribute__ ((__nothrow__));
const u_char * __p_fqname (const u_char *, const u_char *, FILE *) __attribute__ ((__nothrow__));
const char * __p_option (u_long __option) __attribute__ ((__nothrow__));
char * __p_secstodate (u_long) __attribute__ ((__nothrow__));
int __dn_count_labels (const char *) __attribute__ ((__nothrow__));
int __dn_comp (const char *, u_char *, int, u_char **, u_char **)
     __attribute__ ((__nothrow__));
int __dn_expand (const u_char *, const u_char *, const u_char *,
      char *, int) __attribute__ ((__nothrow__));
u_int __res_randomid (void) __attribute__ ((__nothrow__));
int __res_nameinquery (const char *, int, int,
     const u_char *, const u_char *) __attribute__ ((__nothrow__));
int __res_queriesmatch (const u_char *, const u_char *,
      const u_char *, const u_char *) __attribute__ ((__nothrow__));
const char * __p_section (int __section, int __opcode) __attribute__ ((__nothrow__));

int __res_ninit (res_state) __attribute__ ((__nothrow__));
int __res_nisourserver (const res_state,
      const struct sockaddr_in *) __attribute__ ((__nothrow__));
void __fp_resstat (const res_state, FILE *) __attribute__ ((__nothrow__));
void __res_npquery (const res_state, const u_char *, int, FILE *)
     __attribute__ ((__nothrow__));
const char * __res_hostalias (const res_state, const char *, char *, size_t)
     __attribute__ ((__nothrow__));
int __res_nquery (res_state, const char *, int, int, u_char *, int)
     __attribute__ ((__nothrow__));
int __res_nsearch (res_state, const char *, int, int, u_char *, int)
     __attribute__ ((__nothrow__));
int __res_nquerydomain (res_state, const char *, const char *, int,
      int, u_char *, int) __attribute__ ((__nothrow__));
int __res_nmkquery (res_state, int, const char *, int, int,
         const u_char *, int, const u_char *, u_char *,
         int) __attribute__ ((__nothrow__));
int __res_nsend (res_state, const u_char *, int, u_char *, int)
     __attribute__ ((__nothrow__));
void __res_nclose (res_state) __attribute__ ((__nothrow__));

# 21 "lib/http.c" 2
# 1 "/usr/include/poll.h" 1 3 4
# 1 "/usr/include/sys/poll.h" 1 3 4
# 26 "/usr/include/sys/poll.h" 3 4
# 1 "/usr/include/bits/poll.h" 1 3 4
# 27 "/usr/include/sys/poll.h" 2 3 4
# 37 "/usr/include/sys/poll.h" 3 4
typedef unsigned long int nfds_t;


struct pollfd
  {
    int fd;
    short int events;
    short int revents;
  };



# 58 "/usr/include/sys/poll.h" 3 4
extern int poll (struct pollfd *__fds, nfds_t __nfds, int __timeout);
# 72 "/usr/include/sys/poll.h" 3 4

# 1 "/usr/include/poll.h" 2 3 4
# 22 "lib/http.c" 2
# 1 "/usr/include/sys/time.h" 1 3 4
# 27 "/usr/include/sys/time.h" 3 4
# 1 "/usr/include/time.h" 1 3 4
# 28 "/usr/include/sys/time.h" 2 3 4

# 1 "/usr/include/bits/time.h" 1 3 4
# 30 "/usr/include/sys/time.h" 2 3 4
# 39 "/usr/include/sys/time.h" 3 4

# 57 "/usr/include/sys/time.h" 3 4
struct timezone
  {
    int tz_minuteswest;
    int tz_dsttime;
  };

typedef struct timezone *__restrict __timezone_ptr_t;
# 73 "/usr/include/sys/time.h" 3 4
extern int gettimeofday (struct timeval *__restrict __tv,
    __timezone_ptr_t __tz) __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));




extern int settimeofday (__const struct timeval *__tv,
    __const struct timezone *__tz)
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));





extern int adjtime (__const struct timeval *__delta,
      struct timeval *__olddelta) __attribute__ ((__nothrow__));




enum __itimer_which
  {

    ITIMER_REAL = 0,


    ITIMER_VIRTUAL = 1,



    ITIMER_PROF = 2

  };



struct itimerval
  {

    struct timeval it_interval;

    struct timeval it_value;
  };






typedef int __itimer_which_t;




extern int getitimer (__itimer_which_t __which,
        struct itimerval *__value) __attribute__ ((__nothrow__));




extern int setitimer (__itimer_which_t __which,
        __const struct itimerval *__restrict __new,
        struct itimerval *__restrict __old) __attribute__ ((__nothrow__));




extern int utimes (__const char *__file, __const struct timeval __tvp[2])
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));



extern int lutimes (__const char *__file, __const struct timeval __tvp[2])
     __attribute__ ((__nothrow__)) __attribute__ ((__nonnull__ (1)));


extern int futimes (int __fd, __const struct timeval __tvp[2]) __attribute__ ((__nothrow__));
# 191 "/usr/include/sys/time.h" 3 4

# 23 "lib/http.c" 2
# 1 "lib/log.h" 1



typedef enum
{
    logType_none = 0x00,
    logType_terminal = 0x01,
    logType_file = 0x02,
    logType_syslog = 0x04
}logType_t;






void loginit(char *logname, logType_t type, int usePidInName);
void logdeinit(void);
void logout(const char *mes, ...) __attribute__((format(printf, 1, 2)));
void logrenew(void);
# 24 "lib/http.c" 2
# 36 "lib/http.c"
typedef enum
{
    http_open_stage_init,
    http_open_stage_connect,
    http_open_stage_sendhttp,
    http_open_stage_readhttp,
    http_open_stage_connected
}http_open_stages_t;

typedef struct
{
    char location[2048];
    char user_agent[256];
    char path1[1024];
    char hoststr[1024];
    int64_t filesize;
    int64_t off;
    char buffer[7168], *buf_ptr, *buf_end;
    int http_code;
    int line_count;
    int64_t chunksize;
    int willclose;
    int http_socket;
    int https_proto;
    char saved_hoststr[1024];
    struct sockaddr_in servaddr;
    http_open_stages_t stage;
    _Bool need_keepalive;
}http_context_t;

static int http_strncpy(char *dest, const char *src, size_t n)
{
    if(dest)
    {
        strncpy(dest, src, n - 1);
        dest[n- 1] = 0;
    }
    return (((strlen(src)) < (n)) ? (strlen(src)) : (n));
}


static size_t strlcatf(char *dst, size_t size, const char *fmt, ...)
{
    int len = strlen(dst);
    va_list vl;

    __builtin_va_start(vl,fmt);
    len += vsnprintf(dst + len, (int)size > len ? size - len : 0, fmt, vl);
    __builtin_va_end(vl);

    return len;
}


static int http_socket_read(http_context_t *ctx, char *ptr, int size)
{
    int result = -5;
    if(!ptr)
        return -22;
    if(ctx && (ctx->http_socket != -1))
    {
        result = recv(ctx->http_socket, ptr, size, MSG_NOSIGNAL);
    }
    return result;
}


static int lib_http_socket_write(http_context_t *ctx, char *ptr, int size)
{
    int result = -5;
    if(!ptr)
        return -22;
    if(ctx && (ctx->http_socket!= -1))
    {
        result = send(ctx->http_socket, ptr, size, MSG_NOSIGNAL);
    }
    return result;
}


static int http_getc(http_context_t *ctx)
{
    int len;

    if (ctx->buf_ptr >= ctx->buf_end)
    {
        len = http_socket_read(ctx, ctx->buffer, 7168);
        if (len < 0)
        {
            char buffer[128] = { 0, };
            strerror_r((*__errno_location ()), buffer, sizeof(buffer) - 1);
            logout("%s %d: " "Read error %d [%d] - [%s]\n", __FUNCTION__, 127, len, (*__errno_location ()), buffer);
            return len;
        }
        else if (len == 0)
        {
            logout("%s %d: " "End of file\n", __FUNCTION__, 132);
            return -1;
        }
        else
        {
            ctx->buf_ptr = ctx->buffer;
            ctx->buf_end = ctx->buffer + len;
        }
    }
    return *ctx->buf_ptr++;
}


static int http_get_line(http_context_t *ctx, char *line, int line_size)
{
    int ch;
    char *q;
    int tolowcase = 1;

    q = line;
    for(;;) {
        ch = http_getc(ctx);
        if (ch < 0)
            return ch;
        if (ch == '\n') {

            if (q > line && q[-1] == '\r')
                q--;
            *q = '\0';
            return 0;
        } else {
            if ((q - line) < line_size - 1)
            {
                if((q - line) == 8)
                {
                    if(!strncmp(line, "location", 8))
                        tolowcase = 0;
                }

                if(tolowcase)
                    *q++ = tolower(ch);
                else
                    *q++ = ch;
            }
        }
    }
}


static int process_line(http_context_t *ctx, char *line, int line_count, int *new_location)
{
    char *tag, *p, *end;


    if (line[0] == '\0')
        return 0;

    p = line;
    if (line_count == 0) {
        while (!((*__ctype_b_loc ())[(int) ((*p))] & (unsigned short int) _ISspace) && *p != '\0')
            p++;
        while (((*__ctype_b_loc ())[(int) ((*p))] & (unsigned short int) _ISspace))
            p++;
        ctx->http_code = strtol(p, &end, 10);


        if (ctx->http_code >= 400 && ctx->http_code < 600)
            return -lib_http_error_fail_http_error;
    } else {
        while (*p != '\0' && *p != ':')
            p++;
        if (*p != ':')
            return 1;

        *p = '\0';
        tag = line;
        p++;
        while (((*__ctype_b_loc ())[(int) ((*p))] & (unsigned short int) _ISspace))
            p++;
        if (!strcmp(tag, "location")) {
            strcpy(ctx->location, p);
            *new_location = 1;
        } else if (!strcmp (tag, "content-length") && ctx->filesize == -1) {
            ctx->filesize = strtoull(p, ((void *)0), 10);
        } else if (!strcmp (tag, "content-range")) {
            const char *slash;
            if (!strncmp (p, "bytes ", 6)) {
                p += 6;
                ctx->off = strtoull(p, ((void *)0), 10);
                if ((slash = strchr(p, '/')) && (slash[0] != '\0'))
                    ctx->filesize = strtoull(slash + 1, ((void *)0), 10);
            }
        } else if (!strcmp (tag, "transfer-encoding") && !strncasecmp(p, "chunked", 7)) {
            ctx->filesize = -1;
            ctx->chunksize = 0;
        }
        else if (!strcmp (tag, "www-authenticate"))
        {

        }
        else if (!strcmp (tag, "authentication-info"))
        {

        }
        else if (!strcmp (tag, "connection"))
        {
            if (!strcmp(p, "close"))
                ctx->willclose = 1;
        }
    }
    return 1;
}


static int http_connect_first(http_context_t *ctx, const char *path)
{
    int err = -lib_http_error_fail_http_connect;
    char headers[1024] = "";
    int len = 0;


    if(ctx->user_agent[0] != 0)
        len += strlcatf(headers + len, sizeof(headers) - len, "User-Agent: %s\r\n", ctx->user_agent);
    else
        len += strlcatf(headers + len, sizeof(headers) - len, "User-Agent: %s\r\n", "stb100client");
    len += http_strncpy(headers + len, "Accept: */*\r\n", sizeof(headers) - len);
    if(ctx->off)
        len += strlcatf(headers + len, sizeof(headers) - len, "Range: bytes=%lld-\r\n", ctx->off);
    if(ctx->need_keepalive)
        len += http_strncpy(headers + len, "Connection: Keep-Alive\r\n", sizeof(headers)-len);
    else
        len += http_strncpy(headers + len, "Connection: Close\r\n", sizeof(headers)-len);
    len += strlcatf(headers + len, sizeof(headers) - len, "Host: %s\r\n", ctx->hoststr);
    snprintf(ctx->buffer, sizeof(ctx->buffer), "GET %s HTTP/1.1\r\n" "%s\r\n", path, headers);
    err = lib_http_socket_write(ctx, ctx->buffer, strlen(ctx->buffer));
    if(err < 0)
    {
        logout("%s %d: " "Failed %d write data in socket\n", __FUNCTION__, 269, err);
        return -lib_http_error_fail_http_connect;
    }


    ctx->buf_ptr = ctx->buffer;
    ctx->buf_end = ctx->buffer;
    ctx->line_count = 0;
    ctx->off = 0;
    ctx->filesize = -1;
    ctx->willclose = 0;
    ctx->chunksize = -1;

    return 0;
}


static int http_connect_second(http_context_t *ctx, int *new_location)
{
    int err = -lib_http_error_fail_http_connect;
    char line[1024];
    int64_t off = 0;


    for(;;)
    {
        if (http_get_line(ctx, line, sizeof(line)) < 0)
        {
            logout("%s %d: " "Error get line\n", __FUNCTION__, 297);
            return -lib_http_error_fail_http_connect;
        }
        err = process_line(ctx, line, ctx->line_count, new_location);
        if (err < 0)
        {
            logout("%s %d: " "Error process line %s\n", __FUNCTION__, 303, line);
            return err;
        }
        if (err == 0)
            break;
        ctx->line_count++;
    }

    if(off == ctx->off)
        strncpy(ctx->saved_hoststr, ctx->hoststr, sizeof(ctx->saved_hoststr));

    return (off == ctx->off) ? 0 : -lib_http_error_fail_http_connect;
}


static int http_connect(http_context_t *ctx, const char *path, int *new_location)
{
    int err = -lib_http_error_fail_http_connect;
    char line[1024];
    char headers[1024] = "";
    int64_t off = ctx->off;
    int len = 0;


    if(ctx->user_agent[0] != 0)
        len += strlcatf(headers + len, sizeof(headers) - len, "User-Agent: %s\r\n", ctx->user_agent);
    else
        len += strlcatf(headers + len, sizeof(headers) - len, "User-Agent: %s\r\n", "stb100client");
    len += http_strncpy(headers + len, "Accept: */*\r\n", sizeof(headers) - len);
    if(ctx->off)
        len += strlcatf(headers + len, sizeof(headers) - len, "Range: bytes=%lld-\r\n", ctx->off);
    if(ctx->need_keepalive)
        len += http_strncpy(headers + len, "Connection: Keep-Alive\r\n", sizeof(headers)-len);
    else
        len += http_strncpy(headers + len, "Connection: Close\r\n", sizeof(headers)-len);
    len += strlcatf(headers + len, sizeof(headers) - len, "Host: %s\r\n", ctx->hoststr);
    snprintf(ctx->buffer, sizeof(ctx->buffer), "GET %s HTTP/1.1\r\n" "%s\r\n", path, headers);
    err = lib_http_socket_write(ctx, ctx->buffer, strlen(ctx->buffer));
    if(err < 0)
    {
        logout("%s %d: " "Failed %d write data in socket\n", __FUNCTION__, 343, err);
        return -lib_http_error_fail_http_connect;
    }


    ctx->buf_ptr = ctx->buffer;
    ctx->buf_end = ctx->buffer;
    ctx->line_count = 0;
    ctx->off = 0;
    ctx->filesize = -1;
    ctx->willclose = 0;
    ctx->chunksize = -1;


    for(;;)
    {
        if (http_get_line(ctx, line, sizeof(line)) < 0)
        {
            logout("%s %d: " "Error get line\n", __FUNCTION__, 361);
            return -lib_http_error_fail_http_connect;
        }
        err = process_line(ctx, line, ctx->line_count, new_location);
        if (err < 0)
        {
            logout("%s %d: " "Error process line %s\n", __FUNCTION__, 367, line);
            return err;
        }
        if (err == 0)
            break;
        ctx->line_count++;
    }
    if(off == ctx->off)
        strncpy(ctx->saved_hoststr, ctx->hoststr, sizeof(ctx->saved_hoststr));
    return (off == ctx->off) ? 0 : -lib_http_error_fail_http_connect;
}


void lib_http_url_split(char *proto, int proto_size, char *authorization, int authorization_size,
                            char *hostname, int hostname_size, int *port_ptr, char *path, int path_size,
                            const char *url, int *https_proto)
{
    const char *p, *ls, *at, *col, *brk1;

    if(port_ptr)
        *port_ptr = -1;
    if(proto_size > 0)
        proto[0] = 0;
    if(authorization_size > 0)
        authorization[0] = 0;
    if(hostname_size > 0)
        hostname[0] = 0;
    if((path_size > 0) && path)
        path[0] = 0;

    if(https_proto)
    {
        if(!strncmp(url,"https:",6))
            *https_proto = 1;
        else
            *https_proto = 0;
    }


    if ((p = strchr(url, ':')))
    {
        http_strncpy(proto, url, (((proto_size) < (p + 1 - url)) ? (proto_size) : (p + 1 - url)));
        p++;
        if (*p == '/') p++;
        if (*p == '/') p++;
    }
    else
    {

        if(path)
            http_strncpy(path, url, path_size);
        return;
    }

    ls = strchr(p, '/');
    if(!ls)
        ls = strchr(p, '?');
    if(ls)
    {
        if(path)
            http_strncpy(path, ls, path_size);
    }
    else
        ls = &p[strlen(p)];

    if (ls != p)
    {

        if ((at = strchr(p, '@')) && at < ls)
        {
            if(authorization)
                http_strncpy(authorization, p, (((authorization_size) < (at + 1 - p)) ? (authorization_size) : (at + 1 - p)));
            p = at + 1;
        }

        if (*p == '[' && (brk1 = strchr(p, ']')) && brk1 < ls)
        {

            if(hostname)
                http_strncpy(hostname, p + 1, (((hostname_size) < (brk1 - p)) ? (hostname_size) : (brk1 - p)));
            if (brk1[1] == ':' && port_ptr)
                *port_ptr = strtol(brk1 + 2, ((void *)0), 10);
        }
        else if ((col = strchr(p, ':')) && col < ls)
        {
            if(hostname)
                http_strncpy (hostname, p, (((col + 1 - p) < (hostname_size)) ? (col + 1 - p) : (hostname_size)));
            if (port_ptr) *port_ptr = strtol(col + 1, ((void *)0), 10);
        }
        else
        {
            if(hostname)
                http_strncpy(hostname, p, (((ls + 1 - p) < (hostname_size)) ? (ls + 1 - p) : (hostname_size)));
        }
    }
}


int url_join(char *str, int size, const char *proto, const char *authorization, const char *hostname,
                int port, const char *fmt, ...)
{
    str[0] = '\0';
    if (proto)
        strlcatf(str, size, "%s://", proto);
    if (authorization && authorization[0])
        strlcatf(str, size, "%s@", authorization);
    strncat(str, hostname, size);

    if (port >= 0)
        strlcatf(str, size, ":%d", port);
    if (fmt) {
        va_list vl;
        int len = strlen(str);

        __builtin_va_start(vl,fmt);
        vsnprintf(str + len, size > len ? size - len : 0, fmt, vl);
        __builtin_va_end(vl);
    }
    return strlen(str);
}


static int lib_http_create_socket(http_context_t *ctx, const char *host, int port, int blocking, struct sockaddr_in *interface)
{
    int result = -lib_http_error_contex;
    struct hostent *hostEnt=0, hostBuf;
    int tmpLen = 2048,herr;
    char tmp[tmpLen];
    in_addr_t ipaddr;
    int haveaddr;
    int one;

    if(host && ctx)
    {
        haveaddr = 0;
        ipaddr = inet_addr(host);
        if(ipaddr != -1)
            haveaddr = 1;

        if(haveaddr == 0)
        {
            gethostbyname_r(host, &hostBuf, tmp, tmpLen, &hostEnt, &herr);
            if(hostEnt)
            {
                if(hostEnt->h_length == sizeof(ipaddr))
                {
                    memcpy(&ipaddr, hostEnt->h_addr_list[0], hostEnt->h_length);
                    if(ipaddr != -1)
                        haveaddr = 1;
                }
            }
        }

        if(haveaddr)
        {
            ctx->http_socket = socket(2, blocking ? SOCK_STREAM : SOCK_STREAM | SOCK_NONBLOCK, IPPROTO_TCP);
            if(ctx->http_socket != -1)
            {
                struct timeval timeout = { 30, 0};

                if(setsockopt(ctx->http_socket, 1, 20, (char *)&timeout,sizeof(timeout)) < 0)
                    logout("%s %d: " "setsockopt failed\n", __FUNCTION__, 528);

                if (setsockopt(ctx->http_socket, 1, 21, (char *)&timeout,sizeof(timeout)) < 0)
                    logout("%s %d: " "setsockopt failed\n", __FUNCTION__, 531);

                result = 0;
                if(interface)
                {
                    result = bind(ctx->http_socket, (struct sockaddr *)interface, sizeof(*interface));
                    if(result)
                    {
                        logout("%s %d: " "bind failed to address %s : %s\n", __FUNCTION__, 539, inet_ntoa(interface->sin_addr), strerror((*__errno_location ())));
                    }
                }

                if(!result)
                {
                    memset(&ctx->servaddr, 0, sizeof(ctx->servaddr));
                    ctx->servaddr.sin_family = 2;
                    ctx->servaddr.sin_port = htons(port);
                    ctx->servaddr.sin_addr.s_addr = ipaddr;

                    one = 1;
                    if(setsockopt(ctx->http_socket, 1, 9, &one, sizeof(one)) != 0)
                        logout("%s %d: " "Failed set socket keepalive\n", __FUNCTION__, 552);

                    one = 3;
                    if(setsockopt(ctx->http_socket, 6, 6, &one, sizeof(one)) != 0)
                        logout("%s %d: " "Failed set socket keepalive\n", __FUNCTION__, 556);

                    one = 10;
                    if(setsockopt(ctx->http_socket, 6, 4, &one, sizeof(one)) != 0)
                        logout("%s %d: " "Failed set socket keepalive\n", __FUNCTION__, 560);

                    one = 10;
                    if(setsockopt(ctx->http_socket, 6, 5, &one, sizeof(one)) != 0)
                        logout("%s %d: " "Failed set socket keepalive\n", __FUNCTION__, 564);

                    result = 0;
                }
                else
                {
                    shutdown(ctx->http_socket, SHUT_RDWR);
                    close(ctx->http_socket);
                    ctx->http_socket = -1;
                    result = -lib_http_error_fail_connect;
                }
            }
            else
            {
                logout("%s %d: " "Failed(%d) create socket\n", __FUNCTION__, 578, result);
            }
        }
        else
        {

            switch(herr)
            {
                case 1:
                    logout("%s %d: " "Host not found: %s\n", __FUNCTION__, 587, host);
                    break;
                case 4:
                    logout("%s %d: " "The requested name does not have an IP address: \n", __FUNCTION__, 590);
                    break;
                case 3:
                    logout("%s %d: " "A non-recoverable name server error occurred while resolving \n", __FUNCTION__, 593);
                    break;
                case 2:
                    logout("%s %d: " "A temporary error occurred on an authoritative name server while resolving \n", __FUNCTION__, 596);
                    break;
                default:
                    logout("%s %d: " "Unknown error code from gethostbyname_r for \n", __FUNCTION__, 599);
            }
            logout("%s %d: " "Invalid address of host\n", __FUNCTION__, 601);
            result = -lib_http_error_dns;
        }
    }
    else
    {
        logout("%s %d: " "invalid host value\n", __FUNCTION__, 607);
    }
    return result;
}


static void lib_http_delete_socket(http_context_t *ctx)
{
    if(ctx)
    {
        if(ctx->http_socket != -1)
        {
            shutdown(ctx->http_socket, SHUT_RDWR);
            close(ctx->http_socket);
            ctx->http_socket = -1;
        }
    }
}


static int http_open_cnx(http_context_t *ctx, char *resource, unsigned int resource_len, struct sockaddr_in *interface)
{
    int location_changed = 0, redirects = 0;
    int result = -lib_http_error_contex;
    const char *path;
    char hostname[1024];
    char auth[1024];
    int port;
    int https_proto = 0;
    int counter = 0;

    if(ctx)
        result = -lib_http_error_fail_http_error;

    while(ctx)
    {
        lib_http_url_split(((void *)0), 0, auth, sizeof(auth), hostname, sizeof(hostname), &port, ctx->path1, sizeof(ctx->path1), ctx->location, &https_proto);
        ctx->https_proto = https_proto;
        url_join(ctx->hoststr, sizeof(ctx->hoststr), ((void *)0), ((void *)0), hostname, port, ((void *)0));

        if (ctx->path1[0] == '\0')
            path = "/";
        else
            path = ctx->path1;
        if (port < 0)
            port = (ctx->https_proto) ? 443 : 80;


        if(ctx->http_socket != -1)
        {
            int need_delete = 1;

            if(!ctx->willclose)
            {
                if(!strncmp(ctx->saved_hoststr, ctx->hoststr, sizeof(ctx->saved_hoststr)))
                    need_delete = 0;
            }
            if(need_delete == 0)
            {
                int ret = 0;
                struct pollfd ufd;

                memset(&ufd, 0, sizeof (ufd));
                ufd.fd = ctx->http_socket;
                ufd.events = 0x010;
                ret = poll(&ufd, 1, 100);
                if(ret > 0)
                {
                    if((ufd.revents & 0x010) || (ufd.revents & 0x008) || (ufd.revents & 0x020))
                        need_delete = 1;
                }
            }
            if(need_delete)
                lib_http_delete_socket(ctx);
        }

        if(ctx->https_proto)
        {
            result = -lib_http_error_fail_ssl_connect;
            logout("%s %d: " "Failed ssl connect\n", __FUNCTION__, 686);
            break;
        }

        if(ctx->http_socket == -1)
        {
            result = lib_http_create_socket(ctx, hostname, port, 1, interface);
            if(result != 0)
            {
                logout("%s %d: " "%s:%d: Failed create socket for %s\n", __FUNCTION__, 695, __FUNCTION__, 695, hostname);
                break;
            }
            else
            {
                result = connect(ctx->http_socket, (struct sockaddr*)&ctx->servaddr, sizeof(struct sockaddr_in));
                if(result != 0)
                {
                    char buffer[128] = { 0, };
                    strerror_r((*__errno_location ()), buffer, sizeof(buffer) - 1);
                    logout("%s %d: " "Failed connect to host - %s\n", __FUNCTION__, 705, buffer);
                    shutdown(ctx->http_socket, SHUT_RDWR);
                    close(ctx->http_socket);
                    ctx->http_socket = -1;
                    result = -lib_http_error_fail_connect;
                }
            }
        }

        if(resource && resource_len)
            strncpy(resource, path, resource_len);

        result = http_connect(ctx, path, &location_changed);
        if(result != 0)
        {
            if(result == -lib_http_error_fail_http_connect)
            {
                if(counter++ < 1)
                {
                    lib_http_delete_socket(ctx);
                    continue;
                }
            }
            logout("%s %d: " "Failed connect to %s\n", __FUNCTION__, 728, ctx->location);
            break;
        }

        if ((ctx->http_code == 301 || ctx->http_code == 302 || ctx->http_code == 303 || ctx->http_code == 307) && location_changed == 1)
        {

            lib_http_delete_socket(ctx);
            if (redirects++ >= 8)
            {
                logout("%s %d: " "MAX Redirects count %d\n", __FUNCTION__, 738, redirects);
                result = -lib_http_error_fail_http_error;
                break;
            }
            location_changed = 0;
            continue;
        }
        break;
    }

    if(result && (ctx->http_socket != -1))
        lib_http_delete_socket(ctx);

    return result;
}


void lib_http_clear_context(void *ctx)
{
    http_context_t *context = (http_context_t *)ctx;
    if(context)
    {
        memset(context, 0, sizeof(*context));
        context->http_socket = -1;
    }
}

int lib_http_open(void *ctx, int closeConnection, const char *uri, const char *user_agent, const char *content_type, const char *cookie, const char *post_data, int64_t offset, char *resource, unsigned int resource_len, struct sockaddr_in *interface)
{
    http_context_t *context = (http_context_t *)ctx;
    int result = -lib_http_error_contex;
    if(context)
    {
        http_strncpy(context->location, uri, sizeof(context->location));
        if(user_agent)
            http_strncpy(context->user_agent, user_agent, sizeof(context->user_agent));
        else
            context->user_agent[0] = 0;
        context->off = offset;
        context->need_keepalive = closeConnection ? 0 : 1;
        result = http_open_cnx(context, resource, resource_len, interface);
    }
    return result;
}

int lib_http_open_first(void *ctx, int closeConnection, const char *uri, const char *user_agent, int64_t offset, char *resource, unsigned int resource_len, struct sockaddr_in *interface, lib_http_wait_t *waitinfo)
{
    http_context_t *context = (http_context_t *)ctx;
    int result = -lib_http_error_contex;
    int https_proto = 0;
    char hostname[1024];
    char auth[1024];
    int need_delete;
    int port;

    if(context)
    {
        http_strncpy(context->location, uri, sizeof(context->location));
        if(user_agent)
            http_strncpy(context->user_agent, user_agent, sizeof(context->user_agent));
        else
            context->user_agent[0] = 0;
        context->off = offset;
        context->need_keepalive = closeConnection ? 0 : 1;
        context->stage = http_open_stage_init;

        lib_http_url_split(((void *)0), 0, auth, sizeof(auth), hostname, sizeof(hostname), &port, context->path1, sizeof(context->path1), context->location, &https_proto);
        context->https_proto = https_proto;
        url_join(context->hoststr, sizeof(context->hoststr), ((void *)0), ((void *)0), hostname, port, ((void *)0));

        if (port < 0)
            port = (context->https_proto) ? 443 : 80;

        if(context->https_proto)
        {
            result = -lib_http_error_fail_ssl_connect;
            logout("%s %d: " "Failed ssl connect\n", __FUNCTION__, 814);
        }
        else
        {
            if(context->http_socket != -1)
            {
                need_delete = 1;

                if(!context->willclose)
                {
                    if(!strncmp(context->saved_hoststr, context->hoststr, sizeof(context->saved_hoststr)))
                        need_delete = 0;
                }

                if(need_delete)
                {
                    logout("%s %d: " "Need delete socket\n", __FUNCTION__, 830);
                    lib_http_delete_socket(context);
                }
            }

            if(context->http_socket == -1)
            {
                result = lib_http_create_socket(context, hostname, port, 0, interface);
                if(result == 0)
                {
                    result = connect(context->http_socket, (struct sockaddr*)&context->servaddr, sizeof(struct sockaddr_in));
                    if(result == 0)
                    {
                        *waitinfo = lib_http_wait_write;
                        context->stage = http_open_stage_sendhttp;
                        result = lib_http_open_second(context, 0, waitinfo);
                    }
                    else if((result == -1) && ((*__errno_location ()) == 115))
                    {
                        *waitinfo = lib_http_wait_write;
                        context->stage = http_open_stage_connect;
                        result = 0;
                    }
                    else
                    {
                        result = -lib_http_error_fail_connect;
                    }
                }
                else
                {
                    logout("%s %d: " "%s:%d: Failed create socket for %s\n", __FUNCTION__, 860, __FUNCTION__, 860, hostname);
                }
            }
            else
            {
                context->stage = http_open_stage_sendhttp;
                *waitinfo = lib_http_wait_write;
                result = lib_http_open_second(context, 0, waitinfo);
            }
        }
    }
    return result;
}

int lib_http_open_second(void *ctx, int *connected, lib_http_wait_t *waitinfo)
{
    http_context_t *context = (http_context_t *)ctx;
    int result = -lib_http_error_contex;
    int new_location = 0;
    const char *path;

    if(connected)
        *connected = 0;

    if(context)
    {
        switch(context->stage)
        {
            case http_open_stage_init:
                logout("%s:%d: Invalid state 0x%X\n", __FUNCTION__, 889, context->stage);
                break;
            case http_open_stage_connect:
                if(context->http_socket != -1)
                {
                    result = connect(context->http_socket, (struct sockaddr*)&context->servaddr, sizeof(struct sockaddr_in));
                    if(result == 0)
                    {
                        context->stage = http_open_stage_sendhttp;
                        *waitinfo = lib_http_wait_write;
                    }
                    else if((result == -1) && ((*__errno_location ()) == 115))
                    {
                        context->stage = http_open_stage_connect;
                        *waitinfo = lib_http_wait_write;
                        result = 0;
                        break;
                    }
                    else
                    {
                        logout("%s:%d: Failed connect: %s\n", __FUNCTION__, 909, strerror((*__errno_location ())));
                        result = -lib_http_error_fail_connect;
                        break;
                    }
                }
            case http_open_stage_sendhttp:
                if (context->path1[0] == '\0')
                    path = "/";
                else
                    path = context->path1;
                result = http_connect_first(context, path);
                if(result == 0)
                {
                    context->stage = http_open_stage_readhttp;
                    *waitinfo = lib_http_wait_read;
                }
                else
                {
                    logout("%s:%d: Failed write http header\n", __FUNCTION__, 927);
                }
                break;
            case http_open_stage_readhttp:
                result = http_connect_second(context, &new_location);
                if(result == 0)
                {
                    context->stage = http_open_stage_connected;
                    *waitinfo = lib_http_wait_read;
                    if(connected)
                        *connected = 1;
                }
                else
                {
                    logout("%s:%d: Failed read http header\n", __FUNCTION__, 941);
                }
                break;
            case http_open_stage_connected:
                *waitinfo = lib_http_wait_read;
                if(connected)
                    *connected = 1;
                logout("%s:%d: Already connected\n", __FUNCTION__, 948);
                break;
            default:
                logout("%s:%d: Unsupported state 0x%X\n", __FUNCTION__, 951, context->stage);
                break;
        }
    }
    return result;
}

static int http_get_chunk_length(http_context_t *ctx)
{
    char line[64];
    int len = -22;

    if(!ctx->chunksize)
    {
        for(;;)
        {
            do {
                len = http_get_line(ctx, line, sizeof(line));
                if(len < 0)
                    return len;
            } while (!*line);
            ctx->chunksize = strtoull(line, 0, 16);
            if (!ctx->chunksize)
                return 0;
            break;
        }
    }
    else
    {
        logout("%s:%d: It's not chunked session\n", __FUNCTION__, 980);
    }

    return len;
}

int lib_http_read(void *ctx, char *buf, int size)
{
    http_context_t *context = (http_context_t *)ctx;
    int len = -lib_http_error_contex, len2;
    int cnt = 10;

    if(context)
    {
        if(context->chunksize >= 0)
        {
            len2 = 0;
            while(len2 < size)
            {
                if(!context->chunksize)
                {
                    len = http_get_chunk_length(context);
                    if((len < 0) || (!context->chunksize))
                    {
                        break;
                    }
                }


                len = context->buf_end - context->buf_ptr;
                if(len > 0)
                {
                    if(len > size)
                        len = size;
                    if(len > context->chunksize)
                        len = context->chunksize;
                    if(len > size - len2)
                        len = size - len2;
                    memcpy(buf + len2, context->buf_ptr, len);
                    context->buf_ptr += len;
                    context->chunksize -= len;
                    len2 += len;
                    if(!context->chunksize)
                        continue;
                }

                if(len2 < size)
                {
                    len = size - len2;
                    if(len > context->chunksize)
                        len = context->chunksize;
                    len = http_socket_read(context, buf + len2, len);
                    if(len > 0)
                    {
                        context->chunksize -= len;
                        len2 += len;
                        if(!context->chunksize)
                            continue;
                    }
                    else if(len < 0)
                    {
                        break;
                    }
                }
                if(!context->chunksize)
                    if(cnt-- == 0)
                        break;
            }
            len = len2 ? len2 : len;
            if(len > 0)
                context->off += len;
        }
        else
        {

            len = context->buf_end - context->buf_ptr;
            if (len > 0)
            {
                if (len > size)
                    len = size;
                memcpy(buf, context->buf_ptr, len);
                context->buf_ptr += len;
            }
            if(len < size)
            {
                if ((context->filesize >= 0) && (context->off + len >= context->filesize))
                {
                    if(len > 0)
                        context->off += len;
                    return len;
                }
                len2 = http_socket_read(context, buf + len, size - len);
                if(len2 > 0)
                    len += len2;
                else if(!len)
                {
                    if(len2 < 0)
                        len = -lib_http_error_fail_io_error;
                    else
                        len = len2;
                }
            }

            if (len > 0)
                context->off += len;
        }
    }

    return len;
}

int lib_http_check_fill(void *ctx, _Bool flush)
{
    http_context_t *context = (http_context_t *)ctx;
    int result = -1;
    int len2;
    int len;

    if(context)
    {
        len = context->buf_end - context->buf_ptr;
        if(context->buf_ptr != context->buffer)
        {
            memmove(context->buffer, context->buf_ptr, len);
            context->buf_ptr = context->buffer;
            context->buf_end = context->buf_ptr + len;
        }

        if((len < sizeof(context->buffer)) && (((context->filesize >= 0) && (context->off + len < context->filesize)) || (context->filesize == -1)))
        {
            if(context->chunksize >= 0)
            {
                logout("%s:%d: Not implemented\n", __FUNCTION__, 1112);
            }
            else
            {
                len2 = http_socket_read(context, context->buf_end, sizeof(context->buffer) - len);
                if(len2 > 0)
                {
                    context->buf_end += len2;
                    len = context->buf_end - context->buf_ptr;
                }
            }
        }

        if((len == sizeof(context->buffer)) || (context->filesize == len))
        {
            if(flush)
            {
                context->buf_ptr = context->buffer;
                context->buf_end = context->buf_ptr;
                context->off += len;
            }
            result = 0;
        }

        if(!context->chunksize)
            http_get_chunk_length(context);
    }

    return result;
}

int lib_http_get_fd(void *ctx)
{
    http_context_t *context = (http_context_t *)ctx;
    int result = -1;

    if(context)
        result = context->http_socket;

    return result;
}

void lib_http_copy_connection(void *dst, void *src)
{
    http_context_t *dst_context = (http_context_t *)dst;
    http_context_t *src_context = (http_context_t *)src;

    if(dst_context && src_context)
    {
        memcpy(dst_context, src_context, sizeof(http_context_t));
        if(src_context->buf_ptr)
            dst_context->buf_ptr = dst_context->buffer + (src_context->buf_ptr - src_context->buffer);
        if(src_context->buf_end)
            dst_context->buf_end = dst_context->buffer + (src_context->buf_end - src_context->buffer);
        memset(src_context, 0, sizeof(http_context_t));
    }
}

_Bool lib_http_is_keepalive(void *ctx)
{
    http_context_t *context = (http_context_t *)ctx;
    _Bool result = 0;

    if(context)
    {
        if((context->http_socket != -1) && !context->willclose)
        {
            if ((context->filesize >= 0) && (context->off >= context->filesize))
                result = 1;
        }
    }

    return result;
}

void lib_http_close(void *ctx)
{
    http_context_t *context = (http_context_t *)ctx;

    if(context)
    {
        if(context->http_socket != -1)
            lib_http_delete_socket(context);
    }
}

int64_t lib_http_get_filesize(void *ctx)
{
    int64_t filesize = 0;
    http_context_t *context = (http_context_t *)ctx;

    if(context)
        filesize = context->filesize;

    return filesize;
}

uint32_t lib_get_http_context_size()
{
    return sizeof(http_context_t);
}
