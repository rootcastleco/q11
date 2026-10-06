# Huawei Q11 — Canlı Teknik Kayıt

Durum etiketleri: CONFIRMED / LIKELY / UNKNOWN
Kanıt referansı `Lnnn` = `logs/boot_01.clean.txt` satır numarası.

| Alan            | Değer                                                                                   | Durum     |
|-----------------|-----------------------------------------------------------------------------------------|-----------|
| Hardware        | Huawei Q11 STB, middleware `STB_model=Q11` (L504)                                       | CONFIRMED |
| SoC             | HiSilicon **Hi3798MV100** (`CPU: hi3798mv100`, L50)                                      | CONFIRMED |
| CPU             | 4× ARM Cortex-A7 r0p5 (`410fc075`, L3, L54), ARMv7, SMP                                  | CONFIRMED |
| RAM             | 1 GiB DDR (`mem=1G`, `Memory: 566652K/1048576K`, L12, L21); RAM tabanı fiziksel 0x0      | CONFIRMED |
| RAM ayrımı      | CMA 380 MiB @0x18400000 (MMZ, medya) + 4 MiB @0x3FC00000; DSP 8 MiB @0x02000000           | CONFIRMED |
| Flash           | Ham NAND, Toshiba 256 MiB, 8-bit, 3.3 V; eMMC yok, SPI NOR görülmedi                      | CONFIRMED |
| NAND ID         | `98 DA 90 15 F6 16 08 00` (L112); tam parça no. çip üzerinden okunmalı                     | CONFIRMED |
| NAND geometri   | Sayfa 2 KiB, OOB 64 B, blok 128 KiB, 2048 blok, ECC 4bit/512 (HW-Auto) (L114)             | CONFIRMED |
| NAND denetleyici| `hinfc610` (HiSilicon)                                                                    | CONFIRMED |
| UART            | PCB: GND \| RX \| TX \| VCC (soldan sağa, cihaz tarafı)                                 | CONFIRMED |
| UART konsol     | ttyAMA0 = PL011 @0xF8B00000 irq 81, 115200 8N1 (L12, L63). ttyAMA1 @0xF8006000, ttyAMA2 @0xF8B02000 | CONFIRMED |
| UART seviyesi   | 3.3 V: Q11 RX pad = 3.29 V (pull-up, Q11 açık); Q11 TX'i 3.3 V'luk CH341A temiz okudu   | CONFIRMED |
| Adaptör         | Siyah CH341A mini programmer; header `1 2 3 TX RX GND 3.3V`; jumper 2-3 = UART            | CONFIRMED |
| Adaptör seviye  | UART modunda TX = 3.29 V, RX = 3.29 V (boşta) → 3.3 V mantık                             | CONFIRMED |
| Bootloader      | HiSilicon **fastboot** (HiSTB SDK; bölüm adları fastboot/bootargs/loader/loaderdb)       | LIKELY    |
| Bootloader UART | Tamamen sessiz: güç → kernel arası 16.8 s boyunca 0 bayt (timing.tsv)                   | CONFIRMED |
| Bootloader shell| Görülmedi; autoboot/tuş mesajı yok                                                       | UNKNOWN   |
| Kernel          | Linux 3.18.13_s40, `wanlijun@huawei-199`, gcc 4.9.2, #4 SMP 23 Haz 2017 (L2)              | CONFIRMED |
| SDK             | HiSTBLinuxV100R003C00SPC065 (modül sürümleri)                                            | CONFIRMED |
| Cmdline         | Bkz. "boot_01 analizi" (L12)                                                             | CONFIRMED |
| RootFS          | SquashFS, bootloader tarafından RAM'e yüklenip initrd olarak veriliyor → `/dev/ram0` (1:0), salt-okunur (L191-192) | CONFIRMED |
| Yazılabilir FS  | `appdata` (mtdblock16) YAFFS2 rw (L279)                                                  | CONFIRMED |
| FS desteği      | squashfs, jffs2, yaffs, fuse, UDF, tntfs (Tuxera NTFS modülü)                            | CONFIRMED |
| Partition map   | 18 MTD bölümü, cmdline `mtdparts=hinand:` (L12, L118-136)                                 | CONFIRMED |
| DTB             | Device Tree kullanılıyor (`Machine model: Hisilicon`, L5). DTB'nin flash'taki yeri bilinmiyor | CONFIRMED / yer UNKNOWN |
| Secure boot     | Göstergeler: hi_advca.ko (L229), `DieID is locked!` (L208), Verimatrix `vmx_ca` (L461), sessiz bootloader, rootfs RAM'e +0x110 başlıkla yükleniyor | LIKELY    |
| TEE             | Hiçbir TEE/OP-TEE mesajı yok                                                              | UNKNOWN   |
| USB             | EHCI @F9890000 (2 port), EHCI @F9930000 (1 port), OHCI @F9880000/@F9920000, xHCI @F98A0000; usb-storage, usbserial, uvc, btusb, hid derlenmiş | CONFIRMED |
| Ethernet        | `hieth` (HiSilicon), MDIO `himii`, port 0 → PHY adres 1, Generic PHY (L137-138). MAC logda yok | CONFIRMED / MAC UNKNOWN |
| HDMI            | hi_hdmi.ko yüklü; açılışta HDMI "UnPlug" (TV bağlı değil/kapalı) (L488)                   | CONFIRMED |
| Grafik          | hi_fb.ko (framebuffer) + hi_tde.ko (2D) + HIGO 4.0; Mali sürücüsü yüklenmiyor            | CONFIRMED |
| GPU             | SoC'de Mali-450 var (genel bilgi); bu firmware'de GPU sürücüsü görülmedi                 | LIKELY    |
| Video decoder   | hi_vfmw / hi_vdec / hi_vpss / hi_svdec (HiSilicon VFMW)                                   | CONFIRMED |
| Linux shell     | Konsolda login/prompt görülmedi; telnetd yok (L200); mgmt CLI release'te kapalı (L528)   | UNKNOWN   |
| Middleware      | Huawei HMT V100R003C89LTRT01SPC600B001 (2 Ağu 2018) (L475), Blink tabanlı tarayıcı        | CONFIRMED |
| Operatör        | Turkcell Superonline IPTV profili (`iptveds.mstv.superonline.com`, L688)                  | CONFIRMED |
| Recovery method | `loader`/`loaderbak` bölümleri = HiSilicon upgrade loader (USB/OTA güncelleme)           | LIKELY    |

## NAND bölüm haritası (boot_01, L118-136)

Toplam 256 MiB = 0x10000000. Bitiş = son bayt (dahil). Numara = mtdN.

| #  | Ad          | Başlangıç  | Bitiş      | Boyut (hex) | Bayt        | MiB    | İçerik / FS                         | Boot-kritik | Yedek önceliği |
|----|-------------|------------|------------|-------------|-------------|--------|-------------------------------------|-------------|----------------|
|  0 | fastboot    | 0x00000000 | 0x000FFFFF | 0x00100000  |   1048576   |   1.00 | Bootloader (LIKELY)                 | EVET        | 1 (yeri doldurulamaz) |
|  1 | bootargs    | 0x00100000 | 0x0017FFFF | 0x00080000  |    524288   |   0.50 | Ortam/bootargs (LIKELY)             | EVET        | 1 |
|  2 | bootargsBak | 0x00180000 | 0x001FFFFF | 0x00080000  |    524288   |   0.50 | bootargs yedeği (LIKELY)            | evet        | 1 |
|  3 | reserve0    | 0x00200000 | 0x003FFFFF | 0x00200000  |   2097152   |   2.00 | UNKNOWN                             | UNKNOWN     | 1 |
|  4 | reserve0Bak | 0x00400000 | 0x005FFFFF | 0x00200000  |   2097152   |   2.00 | UNKNOWN                             | UNKNOWN     | 1 |
|  5 | loaderdb    | 0x00600000 | 0x0067FFFF | 0x00080000  |    524288   |   0.50 | Upgrade loader bayrakları (LIKELY)  | EVET (LIKELY) | 1 |
|  6 | loaderdbbak | 0x00680000 | 0x006FFFFF | 0x00080000  |    524288   |   0.50 | loaderdb yedeği (LIKELY)            | evet        | 1 |
|  7 | baseparam   | 0x00700000 | 0x007FFFFF | 0x00100000  |   1048576   |   1.00 | Ekran/çıkış parametreleri (LIKELY)  | evet        | 1 |
|  8 | pqparam     | 0x00800000 | 0x008FFFFF | 0x00100000  |   1048576   |   1.00 | Görüntü kalitesi param. (LIKELY)    | hayır       | 2 |
|  9 | logo        | 0x00900000 | 0x00CFFFFF | 0x00400000  |   4194304   |   4.00 | Açılış logosu (LIKELY)              | hayır       | 2 |
| 10 | loader      | 0x00D00000 | 0x014FFFFF | 0x00800000  |   8388608   |   8.00 | Upgrade loader imajı (LIKELY)       | kurtarma    | 1 |
| 11 | loaderbak   | 0x01500000 | 0x01CFFFFF | 0x00800000  |   8388608   |   8.00 | loader yedeği (LIKELY)              | kurtarma    | 1 |
| 12 | kernel      | 0x01D00000 | 0x024FFFFF | 0x00800000  |   8388608   |   8.00 | Kernel imajı (+DTB?) (LIKELY)       | EVET        | 1 |
| 13 | rootfs      | 0x02500000 | 0x088FFFFF | 0x06400000  | 104857600   | 100.00 | SquashFS (+0x110 başlık?)           | EVET        | 1 |
| 14 | Misc        | 0x08900000 | 0x0897FFFF | 0x00080000  |    524288   |   0.50 | UNKNOWN                             | UNKNOWN     | 1 |
| 15 | Factory     | 0x08980000 | 0x0A27FFFF | 0x01900000  |  26214400   |  25.00 | Fabrika verisi: MAC/seri/CA (LIKELY)| UNKNOWN     | 1 (cihaza özgü) |
| 16 | appdata     | 0x0A280000 | 0x0FC7FFFF | 0x05A00000  |  94371840   |  90.00 | YAFFS2 rw (CONFIRMED)               | hayır (LIKELY) | 2 |
| 17 | others      | 0x0FC80000 | 0x0FFFFFFF | 0x00380000  |   3670016   |   3.50 | UNKNOWN                             | UNKNOWN     | 2 |

Not: Stok firmware her açılışta flash'a kendisi yazıyor: `updebug ... hisi_flash_write_partition,
HI_Flash_Write, DataLen=131072` ×2 (L691-696). Hangi bölüm olduğu UNKNOWN. Bu yüzden ardışık
açılışlar arasında bazı bölümlerin hash'i değişebilir; bu bizim yazmamız değildir.

## boot_01 analizi (özet)

- Ham log: `logs/boot_01.log` 137868 bayt, SHA-256 `a12e513b8cfd5de36ce56b9bf9106b601a2d6e6f274490a711d028cbbaff3faf`
- Temiz log: `logs/boot_01.clean.txt` (CR, NUL ve RAMDISK spinner temizlendi)
- Zamanlama: güç verme anı (tek 0x00 baytı) → ilk kernel metni arası **16.8 s tam sessizlik**.
- Kernel cmdline (L12):
  `mem=1G console=ttyAMA0,115200 root=/dev/romblock14 rootfstype=squashfs rootwait mtdparts=hinand:1M(fastboot),512K(bootargs),512K(bootargsBak),2M(reserve0),2M(reserve0Bak),512K(loaderdb),512K(loaderdbbak),1M(baseparam),1M(pqparam),4M(logo),8M(loader),8M(loaderbak),8M(kernel),100M(rootfs),512K(Misc),25M(Factory),90M(appdata),-(others) mmz=ddr,0,0,380M user_debug=31 initrd=0x2500110,0x386f800 root=/dev/ram ramdisk_size=102400 rootfstype=squashfs`
  - Sondaki `initrd=... root=/dev/ram ...` kısmı bootloader tarafından ekleniyor (LIKELY). Son `root=` geçerli:
    root = `/dev/ram` (CONFIRMED, "Mounted root ... on device 1:0").
  - initrd fiziksel 0x02500110, boy 0x386F800 = 59176960 bayt (≈56.4 MiB). 0x110'luk kaydırma imza/başlık
    olabilir (LIKELY, doğrulanmadı).
- Init: `/etc/init.d/rcS` → S00devs, S01udev, S80network, S90modules, S99init; HiSilicon `.ko` modülleri, sonra
  Huawei middleware (vmx_ca, stbService, logger, tarayıcı).
- Ağ kablosu takılı değilken middleware sürekli `eth0 IP` hatası basıyor (log spam).

## Güvenlik kuralları (kalıcı)
- Q11 VCC pini hiçbir zaman adaptöre bağlanmaz; Q11 kendi adaptöründen beslenir.
- 5 V UART yok. CH341A TXD → Q11 RX bağlantısı, ölçümle ≤3.3 V doğrulanmadan yapılmaz.
- Doğrulanmış tam yedek olmadan yazma/silme/saveenv/flash yok.
- Yedek alınana kadar **Ethernet/İnternet bağlama**: firmware operatörün güncelleme sunucusunu arıyor
  (L688); OTA güncelleme NAND'ı değiştirebilir.
- Açma sırası: önce CH341A USB, sonra Q11 gücü. Kapatma: önce Q11, sonra USB.
- Kablolama Q11 adaptörü prizden çekiliyken yapılır; CH341A'da GND'nin yanındaki 3.3V pinine dikkat.

## Ölçüm günlüğü
| Tarih | Ölçüm | Değer | Not |
|-------|-------|-------|-----|
| 2026-10-06 | belirtilmemiş nokta | 3.3 V | Adaptör o sırada programlayıcı modundaydı |
| 2026-10-06 | CH341A TX ↔ GND (UART modu, boşta) | 3.29 V | |
| 2026-10-06 | CH341A RX ↔ GND (UART modu, boşta) | 3.29 V | |
| 2026-10-06 | Q11 RX pad ↔ Q11 GND (Q11 açık) | 3.29 V | Faz 5 koşulu 1 sağlandı |

## Olay günlüğü
- 2026-10-06: Proje başladı. Adaptör CH340G → CH341A olarak değişti.
- 2026-10-06: Kullanıcı yalnız dinleme kablolamasını yaptı (Q11 GND–CH341A GND, Q11 TX–CH341A "RX").
- 2026-10-06: PC taraması: CH341A `USB\VID_1A86&PID_5512` ("USB UART-LPT", CM_PROB_FAILED_INSTALL)
  olarak görünüyor. Bu programlayıcı (EPP/I2C/SPI) modu; UART modu PID_5523 olur. COM portu yok.
  COM3/COM4 Bluetooth SPP portları; adaptörle ilgisi yok.
- Salt-okunur yakalama betiği hazırlandı: tools/uart_capture.ps1 (porta asla yazmaz).
- 2026-10-06 21:42:22: Kullanıcı jumper'ı değiştirip USB'yi yeniden taktı. Aygıt yeniden tanındı
  (LastArrivalDate 21:42:22) ama yine PID_5512 → hâlâ programlayıcı modu.
- 2026-10-06: Kart fotoğrafı alındı (photos/ch341a_header_jumper12.png, yakın çekim
  photos/ch341a_header_zoom.png). Header etiketi: `1 2 3 TX RX GND 3.3V`. Jumper fotoğrafta
  1-2 üzerinde → PID_5512 ile tutarlı. Kullanıcıdan jumper'ı 2-3'e alması istendi.
- 2026-10-06 21:48: Jumper 2-3 → `USB\VID_1A86&PID_5523` "USB-SERIAL CH341 (COM8)", sürücü OK.
- 2026-10-06 21:49:58: Salt-okunur yakalama başladı: COM8, 115200 8N1 → logs/boot_01.log.
- 2026-10-06 21:51:27: CH341A USB'den ayrıldı, geri gelmedi. Yakalama 0 baytla durdu.
- 2026-10-06 21:53:05: Yakalama betiği dayanıklı hale getirildi (port takılınca otomatik açılır,
  kopunca yeniden bağlanır) ve yeniden başlatıldı.
- 2026-10-06 21:53: Kullanıcı ölçümü: CH341A TX = 3.29 V, RX = 3.29 V (UART modu).
- 2026-10-06 21:54-21:56: Kullanıcı "taktım"/"USB tamam" dedi ama PC'de CH341A yoktu.
- 2026-10-06 21:57:52: Kablolar sökülü, USB yeniden takıldı → COM8 geri geldi, sorunsuz.
  Değerlendirme (LIKELY): kablolama sırasında CH341A takıldı/resetlendi; LED USB 5 V'tan yandığı için
  yanık kaldı. Olası tetik: GND kablosunun yandaki 3.3V pinine değmesi ya da toprak farkı boşalması.
- 2026-10-06 22:00:00: Kablolama sırasında CH341A yine koptu (COM8). 22:00:51'de başka USB portunda
  COM10 olarak geri geldi. Kablolar bağlıyken, Q11 kapalıyken aygıt sorunsuz tanındı.
- 2026-10-06 22:02:18: Yakalama COM10 üzerinde başladı.
- 2026-10-06 22:02:51: Q11'e güç verildi (0x00 baytı). 22:03:08 kernel metni başladı.
- 2026-10-06 22:06: Açılış tamamlandı, kayıt durduruldu: 137868 bayt, boot_01.log.
  **Faz 1-3 tamam: yalnız dinleme UART çalışıyor.**
- 2026-10-06 ~22:13: Kullanıcı ölçümü: Q11 RX pad = 3.29 V. **Faz 5'in üç koşulu da sağlandı**
  (Q11 RX 3.3 V, CH341A TX 3.29 V, yalnız dinleme çalışıyor). Kullanıcının boş USB belleği var.
- 2026-10-06 22:13:25 → 22:13:49: CH341A USB port 4'ten (COM10) çıkarılıp port 9'a (COM8) takıldı.
  Betikler artık `-Port auto` ile CH341'in COM numarasını kendileri buluyor.
- 2026-10-06: tools/uart_send.ps1 eklendi: tek satır/Enter gönderir, cevabı logs/session_01.log'a ekler.
  Kalıcı değişiklik riski taşıyan komutları varsayılan olarak reddeder (`-DryRun` ile test edildi).
- 2026-10-06 22:18:31: boot_02 yakalaması COM8'de hazır: hat 10 sn sessiz kalınca bir sonraki açılışı
  150 sn kaydeder.
- 2026-10-06 22:19:43: TX kablosu bağlandı (Q11 kapatılmadan; middleware uptime 00:16:18 sürüyordu).
- 2026-10-06 22:20:22: Kullanıcı onayıyla tek Enter gönderildi (tools/uart_send.ps1 → logs/session_01.log).
  Cevapta prompt ya da yankı yok, yalnızca olağan middleware mesajları. **Seri konsol etkileşimli değil.**
- 2026-10-06: Değerlendirme: bootloader sessiz, konsol shell'i yok, telnet yok, CA/secure boot göstergeleri
  var → firmware operatör tarafından kilitli. Bu kilitleri aşmaya yönelik çalışma yapılmayacak.
  Cihazda bizim tarafımızdan hiçbir yazma yapılmadı (yalnızca okuma + tek Enter).

## Faz 6 — Bootloader'a erişim denemesi (kullanıcının kendi cihazı, homebrew Linux amacı)
Kapsam: yalnızca kendi OS'unu çalıştırmak için bootloader konsoluna ulaşmak. Pay-TV CA (Verimatrix)
ve içerik/imza koruması KAPSAM DIŞI.
Gözlem: bootloader UART çıktısı susturulmuş (16.8 s sessizlik) ama girişi okuyor olabilir.
- 2026-10-06 22:24:56: tools/uart_interrupt.ps1 ile açılış penceresinde Ctrl+C (0x03) gönderildi,
  35 sn. Yalnızca tek kesme baytı; komut değil. Çıktı logs/break_01.log. Sonuç bekleniyor.
- 2026-10-06 22:25: break_01'de kutu ilk denemede yeniden başlamamıştı (uptime 00:21). ^C baytları
  geri yankılandı → UART girişi okunuyor/yankılanıyor.
- 2026-10-06 22:26: Çalışan OS'ta `uname -a` gönderildi: yalnızca yankı, çalışma yok. Sonuç: konsol
  yankısı çekirdek tty katmanından; çalışan sistemde kullanılabilir shell YOK (LIKELY).
- 2026-10-06 22:26: uptime 00:01 → kutu break_01 sırasında yeniden başlamış ama araç erken durduğu için
  açılış penceresi kaçmış.
- 2026-10-06 22:28:05: break_ctrlc — 120 sn boyunca Ctrl+C, erken durmadan. Kullanıcı fişi çek-tak yapacak.
  Bootloader çıktısı kapalı olabilir (kör); işe yaramazsa space/ctrl-b/esc denenecek.
- 2026-10-06 22:28-22:30: break_ctrlc sonucu — 120 sn Ctrl+C flood'u boyunca tam açılış yakalandı;
  kutu sessiz bootloader penceresinden geçip doğrudan "Booting Linux"a gitti. **Ctrl+C autoboot'u
  DURDURMUYOR.** Ctrl+C geçerli "herhangi bir tuş" olduğundan: bootloader ya özel tuş istiyor ya da
  bootdelay=0 (UART kesme kapalı). break_ctrlc.log SHA-256 → logs/HASHES.txt.
- 2026-10-06 22:32-22:34: break_space — 120 sn boşluk flood'u da autoboot'u durdurmadı; kutu normal
  kernel'e geçti. İki "herhangi bir tuş" adayı (Ctrl+C, boşluk) başarısız. **UART break-in devre dışı
  (LIKELY bootdelay=0).** break_space.log SHA-256 → logs/HASHES.txt.

## Durum değerlendirmesi (2026-10-06 22:34)
UART üzerinden bootloader'a girilemiyor. Kendi kodunu çalıştırmak için kalan gerçekçi yollar:
  A) HiSilicon USB BootROM kurtarma modu (NAND'ı power-on'da geçici kısa devre ile atlatıp SoC'yi USB
     indirme moduna düşürmek; HiSilicon USB aracıyla RAM'e bootloader yüklemek). RAM-only = geri
     dönüşlü, AMA donanım kısa devre riski + vendor aracı gerekir. Secure boot OTP yanmışsa imzasız
     bootloader reddedilebilir ("DieID is locked!" kısmi OTP işareti).
  B) Harici NAND programlayıcı (TSOP48): tam yedek + offline analiz/değişiklik. CH341A paralel NAND
     okuyamaz; ayrı programlayıcı gerekir. En invazif.
  C) Farklı donanım (Raspberry Pi vb.) ile Linux hedefine gitmek.
- 2026-10-06 22:38-22:40: flood_set — "set" dizisi (CR'siz) 120 sn boyunca tekrar tekrar gönderildi.
  "Booting Linux" yine görüldü → **"set" de autoboot'u durdurmadı.** flood_set.log SHA-256 →
  logs/HASHES.txt.

## Sonuç (2026-10-06 22:40)
Üç bağımsız "stop string"/kesme adayı (Ctrl+C, boşluk, "set") denendi; üçü de bootloader'ın
autoboot'unu durduramadı. Bu, UART break-in'in bu imajda devre dışı bırakıldığına dair kanıtı
güçlendiriyor (LIKELY → CONFIRMED'e yakın). UART yoluyla bootloader'a erişim için makul deneme
alanı tükendi. Kalan yollar Faz 6 sonundaki A/B/C seçenekleri (Güvenlik Değerlendirmesi notuna bakın).
