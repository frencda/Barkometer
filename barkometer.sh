#!/bin/sh

sudo arecord -D plughw:1,0 -q --buffer-time=5000000 -f dat -c 1 -t wav --max-file-time 60 --use-strftime $HOME/bark/%Y-%m-%d-%H-%M-%S.wav &

while true
    do
        newfile=$(inotifywait -q --format %f -e close_write $HOME/bark)
        sudo ncftpput -u "USERNAME" -p "PASSWORD" -DD -V 192.168.2.1 /VIDEO_RAW_D/bark $HOME/bark/$newfile
    done