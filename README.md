# Barkometer

This is a short bash script for the Raspberry Pi that continuously records via the usb microphone and uploads a file to a FTP server every minute. This is based on the articles by Mark Gibbs at [NetworkWorld](https://www.networkworld.com/article/3112878/internet-of-things/building-a-raspberry-pi-powered-barkometer-part-1.html).

## arecord
```
arecord -D plughw:1,0 \
        -f dat \
        -c 1 \
        -t wav \ 
        --max-file-time 60 \
        --use-strftime $HOME/bark/%Y-%m-%d-%H-%M-%S.wav
```

From the site:
* `arecord` … this is “[a command-line soundfile recorder for the ALSA soundcard driver. It supports several file formats and multiple soundcards with multiple devices](http://linux.die.net/man/1/arecord).” 
* `-D plughw:1,0` … this is where it gets complicated. -D is the switch to select which pulse code modulation (PCM, [a method used to digitally represent sampled analog signals](https://en.wikipedia.org/wiki/Pulse-code_modulation)) plugin to use and pluginhw is the interface that allows you to ignore the sound hardware (it automatically performs sample rate conversion). The arguments 1,0 specify that the sound source we want is  sound card 1 and the number of the device on that card. How can you determine these values? This is a complicated issue but if you plug a USB audio input device into a vanilla Raspbian setup it will be identified as 1,0 … we’ll slice and dice this in a future article.
* `-f dat` … the -f switch specifies the format for recording and dat sets that format to 16 bit, little endian, 48,000 samples per second, in stereo.
* `-c 1 …` sets recording to be single channel and overrides the stereo channel setting specified by the -f switch.
* `-t wav` … specifies that the output is to be in WAV format
* `--max-file-time 60` … specifies that the when the output file has captured sound for 60 seconds, it should be closed and a new output file opened. Keeping this to a low value has two benefits; first, it’s easier to handle 28MB files (which is what 60 seconds of 48,000 samples per second audio generates) than some multiple of that and second, longer recording times seem to cause buffer overruns (the condition where there’s more incoming data than can be stuffed into the output buffer which causes samples to be lost).
* `--use-strftime $HOME/bark/%Y-%m-%d-%H-%M-%S.wav` … [When recording, interpret %-codes in the file name parameter using the strftime facility whenever the output file is opened](http://linux.die.net/man/1/arecord). In this case, the output file will be saved in the subdirectory $HOME/Bark and named something like 2016-09-07-04-42-27.wav.

## Transferring to FTP server

Once the file is recorded in `$HOME/bark`, transfer them to the server using:
```
ncftpput -u admin \
    -p password \
    -DD \
    -V \
    ftpserver \
    /bark \
    $HOME/bark/*.*
```

From the site:
Let’s break this down (see the [manual](http://www.ncftp.com/ncftp/doc/ncftpput.html) page for the ncftpput command line options):

* `-u admin` and `-p password` are the login credentials for the target FTP server
* `-DD` causes the local file to be deleted after successfully uploading it.
* `-V` suppresses the display of the upload progress meter
* `ftpserver` is either the IP address or name of the target FTP server
* `/bark` is the remote directory to store the files in
* `$HOME/bark/*.*` is the specification of the files to be FTPed

## Transferring to FTP

Now what we need to do is automate this so that every time a recording is completed, it gets shipped out to the FTP server. This is where we can use a really cool command, [inotifywait](https://linux.die.net/man/1/inotifywait), to monitor for changes to files and directories. `inotifywait` uses `inotify`, “a Linux kernel subsystem that acts to extend filesystems to notice changes to the filesystem, and report those changes to applications” ([Wikipedia](https://en.wikipedia.org/wiki/Inotify)). This tool is in the package [inotify-tools](https://github.com/rvoicilas/inotify-tools/wiki) which is installed thusly:

`sudo apt-get install inotify-tools`

With `inotifywait` installed, we can set up a BASH script like this:
```
arecord -D plughw:1,0 -q --buffer-time=5000000 -f dat -c 1 -t wav --max-file-time 60 --use-strftime $HOME/bark/%Y-%m-%d-%H-%M-%S.wav &

while true 
    do
        NEWFILE=`inotifywait -q --format %f -e close_write $HOME/bark` 
        ncftpput -u admin -p password -DD ftpserver /bark $HOME/bark/$NEWFILE 
    done
```

The `&` at the end of the `arecord` command tells BASH to run it as a background task.

The `while … done` creates an infinite loop and the line starting with `NEWFILE` breaks down as follows:

* `NEWFILE=` sets a temporary environment variable
* \` this backtick causes everything up to the next backtick to be evaluated as a whole before being passed to the command, in this case, setting the value of `NEWFILE`. Without this, `NEWFILE` would take the value “inotifywait” rather than the output of `inotifywait`
* `inotifywait` blocks until a specific filesystem events occurs
* `-q` prevents the program from printing basic status messages which we don't need
* `--buffer-time=5000000` allocates a buffer of 5 seconds (see below)
* `--format %f` specifies that when the filesystem event occurs, the output from inotifywait will be the name of the file that has been affected
* `-e close_write` this specifies the event to wait for, a file close
* `$HOME/bark` is the subdirectory to be monitored 

So, when a file created by `arecord`, is closed in the `$HOME/bark` subdirectory, `inotifywait` stop blocking and print the name of the closed file which will then be stored in the environment variable `NEWFILE` and the script will resume. The command `ncftpput` will then execute and transfer the file name discovered by `inotifywait` to the FTP server and, voila! Job done!

## Starting automatically

Our final task in this installment is to set our script running when the RPi starts. There are multiple ways to achieve this but we’ll use one of the simplest, editing the user autostart file:

`nano ~/.config/lxsession/LXDE-pi/autostart`

The default desktop for Raspbian is LXDE and  the autostart file's contents will look like this unless you've made changes:
```
@lxpanel --profile LXDE-pi
@pcmanfm --desktop --profile LXDE-pi
@xscreensaver -no-splash
@point-rpi 
```
We need to add a line at the end of the file: 

`@bash /home/pi/barkometer.sh`

This will invoke a new instance of BASH and have it execute our script. Because this is in the context of a user it means that the user has to be logged in so automatic login is a good idea. An important issue is that the user login can’t occur until Raspbian has completed starting all subsystems so we can be certain that, unless there’s a problem, the services we require such as a wireless connection will be established.