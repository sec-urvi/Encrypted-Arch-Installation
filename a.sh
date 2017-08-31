#!/bin/bash

wifi-menu
ping google.com
curl -o /etc/pacman.d/mirrorlist https://www.archlinux.org/mirrorlist/all/                                                                                                                                                                                             
vim /etc/pacman.d/mirrorlist
cfdisk /dev/sda                                                                                                                                                                               

# Make filesystem for EFI
mkfs.fat -F32 /dev/sda1

# Create /boot container
mkfs.ext2 /dev/sda2

# Create crypted LVM with /root and swap
cryptsetup luksFormat /dev/sda3
cryptsetup open /dev/sda3 cryptlvm
pvcreate /dev/mapper/cryptlvm
vgcreate vg0 /dev/mapper/cryptlvm
lvcreate -L 16G vg0 -n swap
lvcreate -l 100%FREE vg0 -n root
mkfs.ext4 /dev/mapper/vg0-root
mkswap /dev/mapper/vg0-swap

# Mount
swapon /dev/mapper/vg0-swap
mount /dev/mapper/vg0-root /mnt
mkdir /mnt/boot
mount /dev/sda2 /mnt/boot
mkdir /mnt/boot/efi
mount /dev/sda1 /mnt/boot/efi

# Install system
pacstrap /mnt base base-devel grub-efi-x86_64 vim git efibootmgr dialog wpa_supplicant

# Generate fstab
genfstab -pU /mnt >> /mnt/etc/fstab

mkdir /mnt/hostrun/
mount --bind /run /mnt/hostrun

# Chroot into our newly installed system 
arch-chroot /mnt /bin/bash
mkdir /run/lvm
mount --bind /hostrun/lvm /run/lvm

# Set timezone, hostname...
ln -sf /usr/share/zoneinfo/Europe/Minsk /etc/localtime
hwclock --systohc --utc
echo archlinux > /etc/hostname        # You can use any name instead of "archlinux"

# Configure locales
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo LANG=en_US.UTF-8 >> /etc/locale.conf

# Set root password
passwd

# Open this file
vim /etc/mkinitcpio.conf
# Edit HOOKS="base ... fsck" with HOOKS="base udev autodetect modconf block keymap encrypt lvm2 resume filesystems keyboard fsck"
# Use "i" key to edit (insert something), ESC and ":wq" to write changes and quit

# Regenerate initrd image
mkinitcpio -p linux

# Change grub config
echo "GRUB_ENABLE_CRYPTODISK=y" >> /etc/default/grub
sed -i "s#^GRUB_CMDLINE_LINUX=.*#GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$(blkid /dev/sda3 -s UUID -o value):lvm resume=/dev/mapper/vg0-swap\"#g" /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

# Install grub
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ArchLinux

# Mount root without any issue
dd bs=512 count=8 if=/dev/urandom of=/crypto_keyfile.bin
chmod 000 /crypto_keyfile.bin
cryptsetup luksAddKey /dev/sda3 /crypto_keyfile.bin
mkinitcpio -p linux
chmod 600 /boot/initramfs-linux*

# If you want to start without password prompt use following line
#sed -i 's\^FILES=.*\FILES="/crypto_keyfile.bin"\g' /etc/mkinitcpio.conf

# Enable Intel microcode CPU updates (if you use Intel processor, of course)
pacman -S intel-ucode
grub-mkconfig -o /boot/grub/grub.cfg

# Some additional security
chmod 700 /boot
chmod 700 /etc/iptables

# Create non-root user, set password
useradd -m -g users -G wheel YOUR_USER_NAME
passwd YOUR_USER_NAME

# Open file
vim /etc/sudoers
# and uncomment string %wheel ALL=(ALL) ALL

# Exit from chroot, unmount system, shutdown, extract flash stick. You made it! Now you have fully encrypted system.
exit
umount -R /mnt
swapoff -a
shutdown now
