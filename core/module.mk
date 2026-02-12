SOURCES="clock.c compat.c embedded_fs.c event.c list.c log.c loopctl.c socket.c strbuffer.c thread.c timer.c"
CFLAGS=""
if [ "$OS" = "darwin" ] ; then
    CFLAGS="-DASTRA_EMBEDDED_ASSETS_BLOB=1"
fi
