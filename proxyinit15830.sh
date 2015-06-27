echo 1032_7 1435421357 1032_8 1203224596548 ProxyrcvReInit.sh 1032_7 15830 Mezo1 1032_8 | openssl enc -a -A -aes-256-cbc -k SuperSecretPWD | gzip -cf | nc -N 10.3.2.6 2234
