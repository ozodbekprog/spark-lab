# Spark ↔ Mac: USB-C kabel orqali SSH

**Holat (2026-11-02):** Wi-Fi orqali SSH ishlaydi — `ssh tony@spark-e2aa.local`
(`190.191.7.147`). USB-C direct hozircha ishlamaydi, chunki Spark kernelida
Apple Mac USB-ID (`05ac:1905`) uchun driver yo'q. Bu papkadagi skript shuni
tuzatadi.

## Nega patch kerak

- Mac USB-C orqali o'zini **CDC-NCM USB qurilmasi** sifatida ko'rsatadi:
  `VID 0x05ac`, `PID 0x1905`, product string "Mac".
- Mac tomonda ikkita interfeys allaqachon bor: `en3` (media 100baseTX) va `en4`.
  Tekshirildi: `networksetup -listallhardwareports` → "Ethernet Adapter (en3/en4)".
- Spark'da `cdc_ncm` moduli bor, lekin uning `id_table`'ida `05ac:1905` yo'q,
  shuning uchun driver qurilmaga bog'lanmaydi va `enx...` interfeys paydo bo'lmaydi.
- Upstream commit [`a5148bc2fa27`](https://git.kernel.org/linus/a5148bc2fa27)
  (2026-04-29, Alex Cheema / EXO Labs) aynan 8 qator qo'shadi. Linux **7.0**da
  bu hali yo'q — tekshirildi: kernel.org `v7.0` manbasida `0x1905` = 0 ta.
  Spark kernel: `7.0.0-1019-nvidia`.
- Yechim: shu 8 qatorli patch bilan `cdc_ncm.ko`ni Spark'da qurib yuklash.

## Papka tarkibi

| Fayl | Nima qiladi |
|---|---|
| `cdc_ncm-v7.0.c` | Linux v7.0 `drivers/net/usb/cdc_ncm.c` (o'zgarmagan) |
| `cdc_ncm-patched.c` | `05ac:1905` qo'shilgan nusxa |
| `0001-apple-1905-mac.patch` | Patch (taqqoslash uchun) |
| `build-and-load.sh` | Spark'da: headers tekshirish → patch → build → insmod → quirk |
| `net-up.sh` | Spark'da: `enx...` ga `10.55.0.2` / `10.56.0.2` berish |
| `mac-net-up.sh` | Mac'da: `en3` → `10.55.0.1`, `en4` → `10.56.0.1` |

## Ogohlantirish

Bu **experimental** usul. Tashqi (out-of-tree) USB modul noto'g'ri bo'lsa USB
stack qotishi yoki kernel panic bo'lishi mumkin. Wi-Fi SSH yoki fizik konsol
zaxira bo'lsin. Secure Boot yoqilgan bo'lsa `insmod` "Key was rejected" beradi —
avval `mokutil --sb-state` bilan tekshiring. Kabelni qayta ulaganda boshqa USB
qurilmalar (klaviatura, sichqoncha, disk) uzilishi mumkin.

## Qadamlar

### 0. Zaxira aloqa

```bash
ssh tony@spark-e2aa.local 'uname -r'
```

Bu ishlamasa, avval Wi-Fi/Ethernetni tuzating — USB-C'ni sinashdan foyda yo'q.

### 1. Papkani Spark'ga ko'chirish

```bash
scp -r ~/Documents/spark-usbc-ssh tony@spark-e2aa.local:~/
```

### 2. Spark'da modulni qurish va yuklash

```bash
ssh tony@spark-e2aa.local
cd ~/spark-usbc-ssh
chmod +x *.sh
sudo bash build-and-load.sh
```

Skript:

1. `linux-headers-$(uname -r)` borligini tekshiradi (yo'q bo'lsa o'rnatadi);
2. `cdc_ncm` modul ekanini tekshiradi (`=y` bo'lsa to'xtaydi);
3. v7.0 manbasiga 2 ta `05ac:1905` yozuvini qo'shadi;
4. `/tmp/spark-cdc-ncm-build/cdc_ncm.ko` ni quradi;
5. stock modulni yuklashdan chiqarib, yangisini `insmod` qiladi;
6. `05ac:1905:k` LPM quirk'ini qo'yadi va USB'ni qayta skanerlaydi.

### 3. Kabelni qayta ulash

USB-C kabelni Spark'dan uzib, yana ulang. Mac tomoni qayta enum bo'ladi.

### 4. Spark'da interfeysni tekshirish

```bash
ip -br link | grep enx
lsusb -d 05ac:1905
dmesg | tail -20
```

`enx...` chiqmasa — pastdagi "Muammolar" bo'limi.

### 5. Spark'da IP berish

```bash
sudo bash ~/spark-usbc-ssh/net-up.sh
```

Skript birinchi `enx` ga `10.55.0.2/24`, ikkinchisiga `10.56.0.2/24` beradi
va NetworkManager'dan uzatadi.

### 6. Mac'da IP berish

```bash
bash ~/Documents/spark-usbc-ssh/mac-net-up.sh
```

`en3` → `10.55.0.1/24`, `en4` → `10.56.0.1/24`.

### 7. SSH

```bash
ping -c 2 10.55.0.2
ssh tony@10.55.0.2
```

Agar `10.55.0.2` javob bermasa, `en4` juftligini sinang:

```bash
ping -c 2 10.56.0.2
ssh tony@10.56.0.2
```

## Muammolar

| Belgisi | Sabab / yechim |
|---|---|
| `enx` umuman yo'q | Modul yuklanmagan (`lsmod | grep cdc_ncm`), `dmesg` da bind xatosi; kabel data kabelmi; Spark'ning to'g'ri USB-C portimi. |
| `enx` bor, carrier 0 | Mac tomoni linkni ko'tarmagan; `sudo ifconfig en3 up`; kabelni almashtirib ko'ring; Mac'da "Allow accessories to connect → Always". |
| `insmod: Key was rejected` | Secure Boot. MOK bilan imzolash yoki Secure Boot'ni o'chirish kerak. |
| `insmod: File exists` / `Unknown symbol` | `cdc_ncm` builtin (`CONFIG_USB_NET_CDC_NCM=y`) yoki modul boshqa kernel uchun qurilgan. `uname -r` va headers mosligini tekshiring. |
| Modul yuklandi, `enx` yo'q | USB qayta skaner: `sudo udevadm trigger --action=add --subsystem-match=usb`; keyin kabelni qayta ulang. |
| SSH "Connection refused" | Spark'da `sudo ufw allow OpenSSH`; `systemctl status ssh`. |
| SSH "Permission denied" | `tony` paroli yoki kaliti; Wi-Fi'da ishlagan usulni ishlating. |

## Qaytarish (rollback)

```bash
sudo modprobe -r cdc_ncm
sudo modprobe cdc_ncm        # stock modul qaytadi
```

Yoki oddiy `reboot` — modul `/lib/modules` ga o'rnatilmagan, shuning uchun
qayta yuklashda stock holat qaytadi. Quirk ham sysfs orqali, rebootda tozalanadi.

Doimiy qilish (ixtiyoriy, ehtiyotkorlik bilan):

```bash
sudo mkdir -p /lib/modules/$(uname -r)/updates
sudo cp /tmp/spark-cdc-ncm-build/cdc_ncm.ko /lib/modules/$(uname -r)/updates/
sudo depmod -a
printf 'w /sys/module/usbcore/parameters/quirks - - - - 05ac:1905:k\n' |
  sudo tee /etc/tmpfiles.d/usbcore-quirk.conf
```

Kernel yangilanganda bu modul eskirib qolishi mumkin — kerak bo'lsa yangidan
quring yoki o'chirib tashlang.

## Manbalar

- [Linux commit a5148bc2fa27 — Apple Mac USB-C direct networking](https://git.kernel.org/linus/a5148bc2fa27)
- [Linux v7.0 cdc_ncm.c](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/net/usb/cdc_ncm.c?h=v7.0)
- [AmeerJ97/apple-ncm-1902-linux-direct-link](https://github.com/AmeerJ97/apple-ncm-1902-linux-direct-link) — 1902 uchun analog patch, build usuli
- [Connecting Your Mac to a PC Over USB-C](https://arewecooked.dev/blog/mac-to-pc-usb-c-networking)
- [EXO Labs e'lonasi](https://x.com/exolabs/status/2094415338209149058)
- [DGX Spark User Guide](https://docs.nvidia.com/dgx/dgx-spark/dgx-spark.pdf)
- [Apple: Allow accessories to connect](https://support.apple.com/en-us/102282)
