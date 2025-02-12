# powerdns
Bash script installation for powerdns with KINDNS best practice guidelines

- First Step:
```
apt install -y git
git clone https://github.com/mhrsq/powerdns
cd powerdns
```

- How to install for Debian 12:
```
bash install.sh
service pdns-recursor status
```

- How to clean the installattion:
```
bash clean.sh
```

Note: After cleaning, the machine need to be rebooted. it will automatically scheduling reboot in 1 minute
