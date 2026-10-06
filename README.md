# Huawei Q11 — UART Reverse Engineering Günlüğü

Bu repo, bir **Huawei Q11** IPTV set-top box'ını (HiSilicon Hi3798MV100 tabanlı) UART üzerinden
incelemenin canlı, kronolojik kaydıdır. Amaç cihaza kendi Linux dağıtımını (Debian/Alpine) harici
bir ortam (USB/microSD) üzerinden çalıştırabilmek; Pay-TV içerik koruması (Verimatrix CA) ya da
imza doğrulamasını aşmak **kapsam dışıdır** ve bu repoda bulunmaz.

UART kayıtları kendi cihazımda, kendi masamda tutuldu. Linux bring-up devamında kullanıcı
izniyle harici REI USB hazırlandı; dahili NAND'a yazma komutu veya `saveenv` uygulanmadı.
USB/ext4 stok Q11 tarafından bağlandı; özel Linux boot henüz doğrulanmadı. İçerik korumasına
müdahale yapılmadı. Güncel deney ve sonraki fiziksel adım: [BRINGUP](docs/BRINGUP.md).

## İçindekiler

- [`Q11_RECORD.md`](Q11_RECORD.md) — canlı teknik kayıt: donanım envanteri, NAND bölüm haritası,
  ölçüm günlüğü, olay günlüğü. Her satır `CONFIRMED` / `LIKELY` / `UNKNOWN` etiketiyle işaretli.
- [`logs/`](logs) — ham ve temizlenmiş UART yakalamaları (açılış logları, kesme/stop-string
  denemeleri), zamanlama dosyaları, SHA-256 hash manifesti (`HASHES.txt`).
- [`photos/`](photos) — kullanılan CH341A UART adaptörünün header/jumper fotoğrafları.
- [`tools/`](tools) — Windows PowerShell araçları (aşağıda açıklanıyor).

## Donanım

| Bileşen | Bilgi |
|---|---|
| Cihaz | Huawei Q11 set-top box (middleware `STB_model=Q11`) |
| SoC | HiSilicon **Hi3798MV100**, 4× ARM Cortex-A7 |
| RAM | 1 GiB DDR |
| Flash | Ham NAND, Toshiba 256 MiB, 8 bit, 3.3 V (ID `98 DA 90 15 F6 16`) |
| UART adaptörü | CH341A (siyah "mini programmer" kartı), jumper UART modunda (2-3), 3.3 V mantık seviyesi doğrulanmış |
| Seri port | 115200 8N1, `ttyAMA0` (PL011) |

Tam donanım envanteri, NAND bölüm haritası (offset/boyut/hex/MiB) ve tüm ölçümler için
[`Q11_RECORD.md`](Q11_RECORD.md) dosyasına bakın.

## Bağlantı şeması

PCB üzerindeki header soldan sağa `GND | RX | TX | VCC` (cihaz tarafı etiketi) olarak dizili.
TX/RX çapraz bağlanır (her uç kendi gönderdiği/dinlediği hattı kendi bakış açısıyla adlandırır):

```
Q11 GND ─────────── CH341A GND
Q11 TX  ──────────▶ CH341A RX
Q11 RX  ◀────────── CH341A TX
Q11 VCC     BAĞLANMAZ (cihaz kendi adaptöründen beslenir)
```

**Güvenlik kuralları** (tüm oturum boyunca uygulandı):
- Q11 VCC hiçbir zaman adaptöre bağlanmadı; cihaz her zaman kendi güç adaptöründen beslendi.
- TX hattı bağlanmadan önce hem CH341A hem Q11 tarafında gerilim ölçüldü, 3.3 V olduğu doğrulandı
  (5 V UART adaptörleriyle doğrudan bağlantı SoC'yi geri dönüşsüz zarar verebilir).
- Dahili NAND'a gereksiz yazma/silme yapılmaz. Güncel kullanıcı kararı: tam NAND yedeği Linux bring-up için önkoşul değildir; yedek projesi başlatılmayacak. Açıkça izin verilen harici USB hazırlığı ayrı bir işlemdir.
- Kablolama her zaman cihaz güçsüzken yapıldı; açma sırası önce adaptör USB'si, sonra cihaz gücü.

## Araçlar (`tools/`)

Hepsi Windows PowerShell 7 ile yazıldı, .NET `System.IO.Ports.SerialPort` kullanır. Hiçbiri
cihazın flash'ına yazmaz; "kalıcı değişiklik" riski taşıyan komutlar kod seviyesinde reddedilir.

| Betik | İşlev |
|---|---|
| `uart_capture.ps1` | Salt-okunur açılış logu yakalayıcı. Porta **hiçbir zaman** yazmaz. Adaptör USB'den çıkıp tekrar takılırsa otomatik yeniden bağlanır, `-Port auto` ile CH341'in o anki COM numarasını kendisi bulur. |
| `uart_send.ps1` | Konsola tek satır (veya yalnızca Enter) gönderir. Gönderilen veri + cevap bir log dosyasına eklenir. `saveenv`, `erase`, `nand write`, `dd`, `reboot` gibi kalıcı/riskli komutları içeren bir regex **denylist** ile varsayılan olarak reddeder (`-Override` yalnızca kullanıcı açıkça onaylarsa). |
| `uart_interrupt.ps1` | Açılış penceresinde **tek bir** kesme karakteri (Ctrl+C, boşluk, Esc, vb.) tekrar tekrar gönderir — amaç, bootloader'ın "herhangi bir tuşa basın" tipi autoboot durdurmasını tetiklemek. Komut göndermez, yalnızca tek bayt. |
| `uart_string_flood.ps1` | Açılış penceresinde kısa bir **metni** (örn. `"set"`) CR eklemeden tekrar tekrar gönderir — U-Boot tarzı `CONFIG_AUTOBOOT_STOP_STR` ("stop string") ihtimalini test etmek için. CR eklenmediği sürece hiçbir komut çalışmaz. |

## Bulgular özeti

- Açılış logu tam olarak yakalandı (bkz. `logs/boot_01.log` / `boot_01.clean.txt`): kernel sürümü,
  NAND geometrisi, 18 parçalık MTD bölüm haritası, USB/Ethernet/HDMI denetleyicileri, middleware
  sürümü ve operatör profili (Turkcell Superonline IPTV) netleşti.
- **Bootloader UART çıktısı tamamen kapalı**: güç verilmesinden kernel'in ilk satırına kadar 16.8
  saniye boyunca tek bir bayt bile gelmiyor.
- Çalışan Linux konsolunda girilen karakterler yankılanıyor (tty katmanı okuyor) ama hiçbir komut
  **çalışmıyor** — kullanılabilir bir shell yok.
- Bootloader'ın autoboot'unu durdurmak için üç bağımsız yöntem denendi, **üçü de başarısız**:
  `Ctrl+C`, boşluk tuşu, ve `"set"` stop-string'i (120'şer saniye, tam güç döngüsü boyunca sürekli
  gönderildi). Sonuç: UART üzerinden bootloader'a kesmeyle girme bu imajda devre dışı bırakılmış
  görünüyor (muhtemelen `bootdelay=0`).
- Secure-boot/CA göstergeleri var (`hi_advca.ko`, OTP `DieID is locked!`, Verimatrix `vmx_ca`),
  kesin doğrulanmadı.

Tüm kanıtlar `CONFIRMED` / `LIKELY` / `UNKNOWN` etiketleriyle [`Q11_RECORD.md`](Q11_RECORD.md)
içinde, log satır numaralarına referansla birlikte kayıtlı.

## Güncel Linux bring-up çalışması (2026-10-07)

Proje devam ediyor. **Henüz Q11 üzerinde özel Linux açılışı veya kullanılabilir shell doğrulanmadı.**
Tamamlanmış UART kesme denemeleri tekrarlanmaz; mevcut loglar korunur.

- Stok cmdline sonunda `root=/dev/ram` var; yalnızca ilk `root=` değerini değiştirmek yeterli değil.
- `himciv200` MMC/SD sürücüsü mevcut ve root mount öncesinde iki denetleyiciyi deniyor. Önceki
  açılışlarda kart algılanmadı; microSD desteği yok sonucu çıkarılamaz.
- USB platform denetleyicileri S90modules sonrasında açılıyor; harici USB root için gerekli modüller
  initramfs içinde bulunmalı veya çekirdeğe gömülü olmalı.
- REI ile gerçek cihaz deneyi tamamlandı: xhci USB disk `/dev/sda1` olarak algılandı;
  ext4 superblock sayacı0→3 ve journal biti değişimi stok sistemin bölümü bağlayıp yazdığını doğruladı.
  Debian/özel initramfs çalışmadı. USB PC'de; güç kesildiği için journal recovery bekliyor.
- Debian bookworm armhf/SysV rootfs, ext4 imajı, MBR USB imajı ve deterministik RAM initramfs
  oluşturma araçları eklendi. Bunlar host tarafı hazırlıktır; imaj yükleme/başlatma yolu hâlâ UNKNOWN.
- NAND yedeği çalışması yok. Factory/CA/DRM bölümleri ve imza atlatma kapsam dışı.
- Doğrudan PC LAN deneyi:100Mbps bağlantı, stok DHCP/ARP/ping doğrulandı. TCP7547/56789/56790
  açık; DIAL açıklaması okundu, SSH/telnet konsolu bulunmadı. PC ağ ayarları geri alındı.
- Xiaomi IR kumandasıyla bir açılış denemesi yapıldı; UART tuş olaylarını ve normal IPTV
  açılışını gördü. Kullanıcı HDMI'da recovery'ye girmediğini doğruladı; shell elde edilmedi.

| Belge | İçerik |
|---|---|
| [ARCHITECTURE](docs/ARCHITECTURE.md) | Önceliklendirilmiş yollar ve mevcut engel |
| [BOOT_FLOW](docs/BOOT_FLOW.md) | Stok initrd, bootargs/loader ve rootfs inceleme hedefleri |
| [ROOTFS](docs/ROOTFS.md) | Debian/initramfs oluşturma ve izinli USB hazırlığı |
| [BRINGUP](docs/BRINGUP.md) | Kesin fiziksel deney, loglar ve kabul ölçütleri |
| [HARDWARE](docs/HARDWARE.md) | Kanıtlı adresler, SD ve grafik/DTB adayları |
| [KERNEL](docs/KERNEL.md) | 3.18.24/4.4.35 kaynak adayları ve build aracı |
| [BOOTROM](docs/BOOTROM.md) | UART bootstrap ile native USB ayrımı; bilinmeyenler |
| [NETWORK](docs/NETWORK.md) | İzole DHCP, stok Ethernet/HTTP/DIAL bulguları ve sınırlı inceleme araçları |
| [MEMORY](docs/MEMORY.md) | MMZ hesabı ve RAM bölgesi doğrulama ihtiyacı |

Yeni araçlar `tools/analysis`, `tools/dtb`, `tools/rootfs`, `tools/kernel`, `tools/uart`, `tools/network`
altında; büyük/generated dosyalar gitignored `artifacts/` altında tutulur.

```powershell
python -m unittest discover -s tests -v
python tools/analysis/boot_report.py logs --output artifacts/boot-report.json
```

OK denemesi tamamlandı; rastgele tuşlarla tekrarlanmaz. Sonraki fiziksel adım, Q11 PCB'sinin
iki yüzünü güç/kablolar çıkarılmış halde fotoğraflayıp kart revizyonu ve etiketli padleri
tanımlamak; [tam tarif](docs/BRINGUP.md). Doğrulanmış BootROM pad/strap veya RAM loader henüz yok.
Belleğe rootfs koymak tek başına boot sağlamaz. Stok mount/init betikleri veya yetkili RAM loader
yolu incelenmeden USB üzerinde rastgele "autorun" / güncelleme dosyaları kullanılmaz.

## Önceki durum değerlendirmesi (tarihsel)

UART yoluyla makul deneme alanı (standart kesme tuşları + stop-string) tükendi. Kalan, daha
invazif seçenekler:

1. **HiSilicon USB BootROM kurtarma modu** — SoC'yi güç verme anında USB indirme moduna düşürüp
   RAM'e geçici bir bootloader yüklemek. RAM-only olduğu için güç kesilince iz bırakmaz, ama
   vendor aracı ve dikkatli donanım müdahalesi gerektirir; secure-boot aktifse imzasız imaj
   reddedilebilir.
2. **Harici NAND programlayıcı (TSOP48 soket)** — çipi sökmeden/sökerek tam offline yedek ve
   analiz. En invazif seçenek, son çare.
3. Hedefi bu cihazdan ayırıp resmi Linux desteği olan başka bir kart (Raspberry Pi vb.) üzerinde
   sürdürmek.

Bu bölüm önceki oturumun değerlendirmesidir; yukarıdaki Linux bring-up devamı güncel çalışma
kararlarını açıklar. Önceki USB BootROM ve NAND seçenekleri doğrulanmış yöntem olarak okunmamalıdır.

## Sorumluluk reddi

Bu çalışma kendime ait bir cihaz üzerinde, eğitim/hobi amaçlı gömülü Linux bring-up çalışmasıdır.
Verimatrix CA ya da başka bir içerik koruma/imza doğrulama mekanizmasını atlatmaya yönelik hiçbir
içerik, araç ya da yöntem bu repoda yer almaz ve alınmayacaktır.
