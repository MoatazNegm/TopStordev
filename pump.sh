#! /bin/sh
echo $@ > /tmp/msgfile;
read ack < /tmp/ackmsg;
