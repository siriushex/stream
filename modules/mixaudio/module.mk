SOURCES="mixaudio.c"
MODULES="mixaudio"

check_cflags()
{
    $APP_C $APP_CFLAGS $1 -x c -o /dev/null -c $MODULE/mixaudio.c >/dev/null 2>&1
}

check_pkgconfig()
{
    command -v pkg-config >/dev/null 2>&1
}

build_ffmpeg_contrib()
{
    if [ ! -x "$SRCDIR/contrib/ffmpeg.sh" ] ; then
        return 1
    fi
    "$SRCDIR/contrib/ffmpeg.sh" >/dev/null 2>&1
}

ffmpeg_configure()
{
    FFMPEG_CONTRIB="$SRCDIR/contrib/build/ffmpeg"

    # Prefer system-provided FFmpeg headers/libs via pkg-config when available.
    # Note: compilation may succeed with default include paths, but we still need
    # proper link flags (libavcodec/libavutil) to avoid undefined references.
    if check_pkgconfig ; then
        CFLAGS="$(pkg-config --cflags libavcodec libavutil 2>/dev/null)"
        LDFLAGS="$(pkg-config --libs libavcodec libavutil 2>/dev/null)"
        if [ -n "$LDFLAGS" ] && check_cflags "$CFLAGS" ; then
            return 0
        fi
    fi

    # Fallback to contrib FFmpeg build (static libs).
    if [ ! -d "$FFMPEG_CONTRIB" ] ; then
        build_ffmpeg_contrib || return 1
    fi
    if [ -d "$FFMPEG_CONTRIB" ] ; then
        CFLAGS="-I$FFMPEG_CONTRIB/"
        LDFLAGS="$FFMPEG_CONTRIB/libavcodec/libavcodec.a $FFMPEG_CONTRIB/libavutil/libavutil.a"
        if check_cflags "$CFLAGS" ; then
            return 0
        fi
    fi

    return 1
}

if ! ffmpeg_configure ; then
    ERROR="libavcodec is not found. install ffmpeg dev libs or use contrib/ffmpeg.sh"
fi
