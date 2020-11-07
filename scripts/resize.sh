#!/usr/bin/env bash
lsblk
echo 1 > /sys/class/block/sda/device/rescan
fdisk -l
sudo growpart /dev/sda 3
resize2fs /dev/sda3
lsblk
df -h