# Huawei Q11 — UART Reverse Engineering Günlüğü

Bu repo, bir **Huawei Q11** IPTV set-top box'ını (HiSilicon Hi3798MV100 tabanlı) UART üzerinden
incelemenin canlı, kronolojik kaydıdır. Amaç cihaza kendi Linux dağıtımını (Debian/Alpine) harici
bir ortam (USB/microSD) üzerinden çalıştırabilmek; Pay-TV içerik koruması (Verimatrix CA) ya da
imza doğrulamasını aşmak **kapsam dışıdır** ve bu repoda bulunmaz.

Kayıtlar kendi cihazımda, kendi masamda, tamamen non-destrüktif (yalnızca okuma) yöntemlerle
tutuldu. Hiçbir noktada flash'a yazma, ortam değişkeni kaydetme (`saveenv`) ya da içerik koruması
ile ilgili bir müdahale yapılmadı.

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
- Doğrulanmış tam NAND yedeği alınmadan hiçbir yazma/silme komutu çalıştırılmadı/çalıştırılmayacak.
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

## Durum ve sıradaki adımlar

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

Bu repo, cihaz üzerinde herhangi bir kalıcı/yazma işlemi yapılmadan **mevcut durumda** dondurulmuş
bir kayıttır. Güncellemeler olursa `Q11_RECORD.md`'nin olay günlüğü bölümüne eklenecektir.

## Sorumluluk reddi

Bu çalışma kendime ait bir cihaz üzerinde, eğitim/hobi amaçlı gömülü Linux bring-up çalışmasıdır.
Verimatrix CA ya da başka bir içerik koruma/imza doğrulama mekanizmasını atlatmaya yönelik hiçbir
içerik, araç ya da yöntem bu repoda yer almaz ve alınmayacaktır.
