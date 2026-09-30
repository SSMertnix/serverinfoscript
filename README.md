# EliteHost ServerInfo

**Pterodactyl hosting serverlari uchun professional server-info va monitoring CLI utilitasi.**
Debian 12 (bookworm) va Debian 13 (trixie) uchun optimallashtirilgan, Bash 5.x da ishlaydi.

`serverinfo` bitta buyruq bilan tizim, CPU, RAM, disk, tarmoq, Docker, Pterodactyl Panel / Wings
va o'yin serverlarining holatini chiroyli, rangli va tartibli ko'rinishda chiqaradi.
Bu oddiy neofetch emas — ma'lumotlar hosting node'lari uchun moslashtirilgan.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/SSMertnix/serverinfoscript/HEAD/install.sh)
```

---

## Imkoniyatlar

- **Premium terminal dizayni** — EliteHost logotipi (gradient), ramkali sarlavha, rangli progress-barlar, holat indikatorlari
- **Pterodactyl aniqlash** — Panel, Wings, `wings` servisi, Docker va o'yin serverlari soni (jami / online / offline)
- **Aniq server hisobi** — Wings API → Docker (+ Wings `states.json`) → Panel DB. Aniqlab bo'lmasa `N/A`, hech qachon taxminiy son emas
- **CPU** — model, fizik yadrolar, thread'lar, real-time yuklanish, load average, joriy/maksimal chastota, harorat
- **RAM** — total, used, available, free, cached, usage %, swap (total/used/free)
- **Storage** — NVMe SSD / SSD / HDD / virtual disk aniqlash, RAID/LVM/LUKS qatlamlari, barcha fayl tizimlari
- **Network** — asosiy interfeys, IPv4/IPv6, public IP, gateway, DNS, RX/TX, link speed, holat
- **Health status** — CPU / RAM / STORAGE / WINGS / DOCKER / PTERODACTYL va umumiy (OVERALL) baho
- **Live rejim** — har 2 soniyada yangilanadigan monitor (`q` yoki `Ctrl+C` bilan chiqish)
- **JSON rejim** — skriptlar va monitoring tizimlari uchun toza, valid JSON (ANSI ranglarsiz)
- **Xavfsizlik birinchi o'rinda** — token, parol va `.env` qiymatlari hech qachon chiqarilmaydi
- **Tez** — to'liq hisobot ~0.5–0.7 s (shundan 0.4 s — aniq CPU o'lchash oynasi)

---

## Talablar

| Talab | Izoh |
|---|---|
| OS | Debian 12 yoki Debian 13 (VPS va bare-metal, minimal o'rnatish ham) |
| Shell | Bash 5.x |
| Huquq | O'rnatish uchun `root`. Ishlatish — istalgan foydalanuvchi (to'liq ma'lumot root bilan) |
| Paketlar | `curl`, `jq`, `iproute2`, `procps`, `util-linux`, `ca-certificates` — installer yetishmayotganlarini o'zi o'rnatadi |
| Online o'rnatish | `curl` yoki `wget` (+ `tar`, `gzip` — Debian'da doim bor) |

Barcha paketlar ixtiyoriy: biror buyruq bo'lmasa, `serverinfo` yiqilmaydi — o'sha qiymat `N/A` bo'lib chiqadi.
`lm-sensors` shart emas: harorat to'g'ridan-to'g'ri kernel `hwmon`/`thermal` interfeysidan o'qiladi.

---

## O'rnatish

### ⚡ Online — bitta buyruq (tavsiya etiladi)

Serverda **root** sifatida:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/SSMertnix/serverinfoscript/HEAD/install.sh)
```

`sudo` bilan (oddiy foydalanuvchidan):

```bash
curl -fsSL https://raw.githubusercontent.com/SSMertnix/serverinfoscript/HEAD/install.sh | sudo bash
```

`curl` bo'lmasa — `wget` bilan:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/SSMertnix/serverinfoscript/HEAD/install.sh)
```

> ⚠️ `sudo bash <(curl ...)` ishlamaydi — `sudo` process substitution fayl deskriptorini yopib qo'yadi.
> sudo kerak bo'lsa, yuqoridagi `curl ... | sudo bash` shaklidan foydalaning.
>
> ⚠️ Bir qatorli o'rnatish uchun GitHub repo **public** bo'lishi kerak
> (private repo'dan `raw.githubusercontent.com` 404 qaytaradi — pastdagi "Private repo" bo'limiga qarang).

Online rejimda installer:

1. Bash, `root` huquqi va Debian versiyasini (12 yoki 13) tekshiradi
2. `HEAD` (yoki `--ref`) ni **aniq commit'ga bog'laydi** va o'sha commit'ning **bitta arxivini** HTTPS orqali yuklaydi —
   barcha fayllar bir xil versiyadan bo'ladi
3. Arxivni tekshiradi (imzo, `bash -n` sintaksis, SHA-256), faqat `serverinfo` va `uninstall.sh` ni oladi
4. Yetishmayotgan paketlarni **faqat kerak bo'lsa** `apt` orqali o'rnatadi
5. `/usr/local/bin/serverinfo` ga o'rnatadi (atomar), uninstaller, konfiguratsiya va bash completion qo'shadi
6. Self-test (`serverinfo --json`) bilan tekshiradi, vaqtinchalik fayllarni o'chiradi

| Parametr | Vazifasi |
|---|---|
| `--ref REF` | Aniq versiya: branch, tag yoki commit (standart: `HEAD` = default branch) |
| `--uninstall` | O'chirish (`--yes`, `--keep-config` bilan birga) |
| `--online` | Yonida lokal fayllar bo'lsa ham GitHub'dan yuklash |
| `--force` | Qo'llab-quvvatlanmaydigan OS'da ham o'rnatish (masalan Ubuntu) |
| `--skip-deps` | `apt` orqali paket o'rnatmaslik |
| `--no-color` | Ranglarsiz chiqish |
| `-h`, `--help` | Yordam |

Parametrlar bir qatorli buyruqqa oxiridan qo'shiladi:

```bash
# aniq versiya: tag (masalan v1.0.0 - GitHub'da shunday tag/release yaratilgan bo'lsa) yoki commit SHA.
# commit SHA - eng xavfsiz, o'zgarmaydigan o'rnatish
bash <(curl -fsSL https://raw.githubusercontent.com/SSMertnix/serverinfoscript/HEAD/install.sh) --ref v1.0.0

# sudo + parametr
curl -fsSL https://raw.githubusercontent.com/SSMertnix/serverinfoscript/HEAD/install.sh | sudo bash -s -- --ref v1.0.0

# yuklangan serverinfo faylining SHA-256 si mos kelmasa - o'rnatish to'xtatiladi
SERVERINFO_SHA256=<sha256> bash <(curl -fsSL https://raw.githubusercontent.com/SSMertnix/serverinfoscript/HEAD/install.sh)
```

| O'zgaruvchi | Vazifasi |
|---|---|
| `SERVERINFO_REF` | `--ref` bilan bir xil |
| `SERVERINFO_SHA256` | Kutilgan SHA-256 (mos kelmasa — to'xtaydi) |
| `SERVERINFO_REPO` | Fork'dan o'rnatish (`owner/name`) |
| `GITHUB_TOKEN` / `SERVERINFO_GITHUB_TOKEN` | Faqat private repo uchun o'qish tokeni |

**Yangilash** — o'sha buyruqni qayta ishga tushiring (konfiguratsiya saqlanib qoladi).
**O'chirish** — `serverinfo --uninstall` yoki `bash <(curl -fsSL .../install.sh) --uninstall`.

#### Private repo

Repo private bo'lsa, `repo` (yoki fine-grained "Contents: Read") huquqli token bilan:

```bash
export GITHUB_TOKEN=github_pat_xxxxxxxx
bash <(curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" \
  https://raw.githubusercontent.com/SSMertnix/serverinfoscript/HEAD/install.sh)
```

Installer tokenni faqat `api.github.com` ga va faqat `curl` ning stdin konfiguratsiyasi orqali yuboradi
(buyruq qatorida/`ps` da ko'rinmaydi). Eng qulay yo'l — repo'ni **public** qilish:
GitHub → Settings → General → Danger Zone → *Change visibility*.

### 📦 Lokal — fayllardan

Loyiha fayllarini (`install.sh`, `uninstall.sh`, `serverinfo`) **bitta papkaga** joylang (yoki `git clone`), so'ng:

```bash
chmod +x install.sh
sudo ./install.sh
```

Lokal rejimda installer internetdan hech narsa yuklamaydi — hamma narsa yonidagi fayllardan o'rnatiladi.
Qayta ishga tushirish xavfsiz: mavjud o'rnatish yangilanadi, konfiguratsiya saqlanib qoladi.

---

## Foydalanish

| Buyruq | Natija |
|---|---|
| `serverinfo` | To'liq hisobot: SYSTEM, CPU, MEMORY, STORAGE, NETWORK, DOCKER, PTERODACTYL, STATUS |
| `serverinfo --live` | Live monitor, har 2 soniyada yangilanadi (`q` / `Ctrl+C` — chiqish) |
| `serverinfo --cpu` | Faqat CPU |
| `serverinfo --ram` | RAM va swap (`--memory`) |
| `serverinfo --disk` | Disklar (`--storage`) |
| `serverinfo --network` | Tarmoq + qo'shimcha interfeyslar (`--net`) |
| `serverinfo --pterodactyl` | Panel, Wings, Docker va o'yin serverlari (`--ptero`) |
| `serverinfo --docker` | Docker engine |
| `serverinfo --status` | Health status (`--health`) |
| `serverinfo --system` | Tizim ma'lumotlari |
| `serverinfo --json` | Valid JSON (bo'lim parametrlari bilan birga ishlaydi) |
| `serverinfo --no-color` | Ranglarsiz (`NO_COLOR` o'zgaruvchisi ham qo'llab-quvvatlanadi) |
| `serverinfo --live -i 5` | Live rejim, 5 soniyalik interval (1–60) |
| `serverinfo --public-ip` | NAT ortida public IP ni aniqlash uchun bitta HTTPS so'rovga ruxsat |
| `serverinfo --help` | Yordam |
| `serverinfo --version` | Versiya |
| `serverinfo --uninstall` | Dasturni o'chirish |

Bo'limlarni birlashtirish mumkin: `serverinfo --cpu --ram` yoki qisqacha `serverinfo -cr`.

### Namuna

```text
 PTERODACTYL
 ──────────────────────────────────────────────────────────
 Panel          DETECTED  v1.11.10
 Panel Path     /var/www/pterodactyl
 Web Server     nginx (active)
 Queue Worker   pteroq (active)
 Wings          ONLINE  v1.11.13
 Wings API      :8080 (HTTPS)  ·  SFTP :2022
 Docker         RUNNING
 Game Data      /var/lib/pterodactyl/volumes
 Data Disk      23.0% used · 1.4 TiB free (/)
 Servers        24
 Online         18
 Offline        5
 Starting       1
 Suspended      2
 Source         Wings API

 STATUS
 ──────────────────────────────────────────────────────────
 ● CPU          HEALTHY    23.4%
 ● RAM          HEALTHY    32.8%
 ● STORAGE      HEALTHY    23.0% (/)
 ● WINGS        ONLINE
 ● DOCKER       RUNNING
 ● PTERODACTYL  DETECTED   24 servers · 18 online
 ────────────────────────
 ● OVERALL      HEALTHY
```

Pterodactyl topilmasa:

```text
 PTERODACTYL
 ──────────────────────────────────────────────────────────
 Status         NOT DETECTED
```

---

## Pterodactyl aniqlash

`serverinfo` Pterodactyl'ni **faqat aniqlaydi** — hech narsani o'rnatmaydi, ishga tushirmaydi yoki o'zgartirmaydi.

**Panel** quyidagilar orqali aniqlanadi:
- `/var/www/pterodactyl` va boshqa standart yo'llar (`PANEL_DIR` bilan o'zgartirish mumkin)
- nginx (`/etc/nginx/sites-enabled`, `conf.d`) va apache (`/etc/apache2/sites-enabled`) konfiguratsiyalaridagi `root .../public`
- Tasdiqlash: `artisan` fayli + `config/pterodactyl.php` yoki `composer.json` dagi `pterodactyl/panel`
- Versiya `config/app.php` dan, queue worker holati `pteroq` servisidan olinadi

**Wings**: `/usr/local/bin/wings`, `/etc/pterodactyl/config.yml` yoki `wings` systemd unit'i.
Holat `systemctl is-active wings` mantig'i bilan aniqlanadi: `active` → **ONLINE**, aks holda **OFFLINE**,
Wings yo'q bo'lsa → **NOT INSTALLED**. systemd bo'lmagan muhitda jarayonlar jadvali tekshiriladi.

### Serverlarni sanash — usullar tahlili

| Usul | Aniqlik | Kamchiligi | Qaror |
|---|---|---|---|
| **Wings API** (`GET /api/servers`, lokal) | Eng aniq: Wings'ning o'zi ko'rgan real holat (running / starting / offline / suspended) | root kerak (token `config.yml` da) | **1-usul** |
| **Docker konteynerlari** (Wings label'lari: `Service=Pterodactyl`, `ContainerType=server_process`) + Wings `states.json` | Online soni real-time; konteyneri yo'q serverlar `states.json` orqali qo'shiladi | root yoki `docker` guruhi | **2-usul** (Wings API ishlamasa) |
| **Panel ma'lumotlar bazasi** (faqat `COUNT(*)`) | Serverlar va node'lar soni aniq, lekin power holati DB'da saqlanmaydi | Panel shu serverda bo'lishi, root | Node jami soni uchun qo'shimcha manba; faqat Panel bo'lgan serverda jami son |
| **Panel API** | API key yaratish va har bir server uchun alohida so'rov talab qiladi (sekin) | qo'lda sozlash | Ishlatilmaydi |

Qoidalar:
- Hech bir usul aniq natija bermasa: **`Servers N/A`** (taxminiy son hech qachon chiqarilmaydi)
- JSON rejimida noma'lum qiymatlar `null` bo'ladi
- `Source` qatori raqamlar qaysi manbadan olinganini ko'rsatadi (`Wings API`, `Docker`, `Docker + Panel DB`, `Panel DB`)

---

## Health status

| Ko'rsatkich | HEALTHY | WARNING | Yuqori |
|---|---|---|---|
| CPU | < 70% | 70–90% | ≥ 90% → **HIGH** |
| RAM | < 80% | 80–90% | ≥ 90% → **CRITICAL** |
| STORAGE | < 80% | 80–90% | ≥ 90% → **CRITICAL** |
| WINGS | `active` → **ONLINE** | | `inactive` → **OFFLINE** |

STORAGE barcha yoziladigan fayl tizimlari ichidan eng to'lganiga qarab baholanadi (qaysi mount ekani ko'rsatiladi).
**OVERALL**: har qanday HIGH/CRITICAL, Wings OFFLINE yoki Wings bor-u Docker ishlamayotgan bo'lsa → CRITICAL.
Chegaralarni konfiguratsiyada o'zgartirish mumkin.

---

## JSON

```bash
serverinfo --json
serverinfo --pterodactyl --json | jq .pterodactyl
```

```json
{
  "elitehost": { "tool": "serverinfo", "name": "EliteHost ServerInfo", "version": "1.0.0", "generated_at": "2026-09-29T16:18:47+05:00" },
  "system": { "os": "Debian GNU/Linux 13 (trixie)", "debian_version": "13.1", "kernel": "6.12.43+deb13-amd64", "architecture": "x86_64", "hostname": "elite-node-01" },
  "cpu": { "model": "Intel Xeon W-2295 @ 3.00GHz", "cores": 18, "threads": 36, "usage_percent": 23.4, "load_average": [0.42, 0.38, 0.31] },
  "memory": { "total": "125.6 GiB", "total_bytes": 134862237696, "used": "41.2 GiB", "usage_percent": 32.8 },
  "storage": { "device_type": "NVMe SSD", "total": "1.8 TiB", "used": "421.3 GiB", "free": "1.4 TiB", "usage_percent": 23.0 },
  "pterodactyl": { "detected": true, "servers": 24, "online": 18, "offline": 5, "starting": 1, "source": "Wings API" },
  "health": { "cpu": "HEALTHY", "ram": "HEALTHY", "storage": "HEALTHY", "wings": "ONLINE", "overall": "HEALTHY" }
}
```

(Qisqartirilgan namuna. Haqiqiy chiqishda barcha bo'limlar to'liq; baytlar `*_bytes` maydonlarida, odam o'qiydigan qiymatlar yonida.)

---

## Konfiguratsiya

Fayl: `/etc/elitehost/serverinfo.conf` (installer yaratadi, qayta o'rnatishda saqlanadi).
Fayl **faqat o'qiladi (parse)**, hech qachon bajarilmaydi (`source` qilinmaydi); noto'g'ri qiymatlar e'tiborsiz qoldiriladi.

| Kalit | Standart | Tavsif |
|---|---|---|
| `BRAND_COLOR` | `135` | EliteHost asosiy rangi (256-rang palitra indeksi) |
| `LOGO_COLORS` | `129 135 99 105 69 75` | Logotip gradienti (har qatorga bittadan) |
| `PUBLIC_IP_LOOKUP` | `no` | NAT ortida public IP uchun tashqi HTTPS so'rov |
| `PUBLIC_IP_URL` | `https://api.ipify.org` | Public IP servisi (faqat `https://`) |
| `WINGS_CONFIG` | `/etc/pterodactyl/config.yml` | Wings konfiguratsiyasi |
| `PANEL_DIR` | *(avto)* | Panel papkasi |
| `WINGS_API` | `auto` | `off` — Wings API so'rovini o'chirish |
| `PANEL_DATABASE` | `auto` | `off` — Panel DB so'rovini o'chirish |
| `CPU_WARN` / `CPU_CRIT` | `70` / `90` | CPU chegaralari (%) |
| `RAM_WARN` / `RAM_CRIT` | `80` / `90` | RAM chegaralari (%) |
| `DISK_WARN` / `DISK_CRIT` | `80` / `90` | Disk chegaralari (%) |
| `LIVE_INTERVAL` | `2` | Live rejim intervali (1–60 s) |

---

## Xavfsizlik

- **Hech qachon chiqarilmaydi:** Wings token, DB parol, API tokenlar, `.env` qiymatlari, `/root/.bash_history`, SSH kalitlar, Cloudflare tokenlar
- Wings tokeni `curl` ga faqat **stdin** orqali (`--config -`) beriladi — `ps` / `/proc/*/cmdline` da ko'rinmaydi; `~/.curlrc` o'qilmaydi (`curl -q`), proxy orqali yuborilmaydi (`--noproxy`)
- Token faqat Wings porti **root'ga tegishli** jarayon tomonidan tinglanayotgan bo'lsa yuboriladi — oddiy foydalanuvchi portni egallab olsa, token unga berilmaydi
- HTTPS'da sertifikat tekshiriladi (`--resolve` bilan to'g'ri hostname; self-signed bo'lsa aynan shu sertifikat bilan)
- Wings API javobidagi server environment o'zgaruvchilari (RCON parollari va h.k.) ekranga chiqmaydi — faqat `jq` hisoblagan sonlar olinadi
- Panel DB: ulanish ma'lumotlari `mariadb` ga anonim pipe (`--defaults-file=/dev/fd/3`) orqali uzatiladi — argv, environment yoki boshqa `my.cnf` fayllar orqali emas; `LOCAL INFILE` o'chirilgan (`--local-infile=0`); faqat `COUNT(*)` so'rovlari
- www-data'ga tegishli Panel fayllari (`.env`, `config/app.php`, `composer.json`) faqat oddiy fayl bo'lsa, hajmi va vaqti cheklangan holda o'qiladi (FIFO/symlink hujumlari serverinfo'ni osib qo'ya olmaydi)
- Panel papkasidagi PHP kod **ishga tushirilmaydi** (`php artisan` yo'q) — www-data → root privilege escalation xavfi yo'q
- To'xtatilgan Docker "uyg'otilmaydi": `docker.socket` faol bo'lsa ham, engine ishlamayotganda Docker API'ga murojaat qilinmaydi
- Tizimdan olingan barcha matnlar boshqaruv belgilari va noto'g'ri UTF-8 baytlardan tozalanadi (terminal escape injection himoyasi, JSON doim valid)
- `serverinfo` o'zi internetdan kod yuklamaydi va masofaviy skript bajarmaydi; yagona ixtiyoriy tashqi so'rov — `PUBLIC_IP_LOOKUP` (standartda o'chiq)
- Online installer faqat shu loyihaning GitHub repo'sidan, faqat HTTPS (TLS 1.2+) orqali, **aniq commit'ga bog'langan** bitta arxivni yuklaydi;
  `--ref`/repo nomlari qat'iy tekshiriladi, arxiv egalari/huquqlari qabul qilinmaydi, fayllar imzo + sintaksis + (ixtiyoriy) SHA-256 bilan tekshiriladi.
  Maksimal ishonch uchun: `--ref <commit>` va `SERVERINFO_SHA256` bilan o'rnating

---

## O'chirish (Uninstall)

```bash
sudo serverinfo --uninstall        # yoki: sudo ./uninstall.sh
bash <(curl -fsSL https://raw.githubusercontent.com/SSMertnix/serverinfoscript/HEAD/install.sh) --uninstall
```

| Parametr | Vazifasi |
|---|---|
| `-y`, `--yes` | Tasdiq so'ramasdan o'chirish |
| `--keep-config` | `/etc/elitehost/serverinfo.conf` ni saqlab qolish |

Faqat EliteHost ServerInfo imzosi (`ELITEHOST-SERVERINFO`) bor fayllar o'chiriladi, `rm -rf` ishlatilmaydi,
papkalar faqat bo'sh bo'lsa o'chiriladi. Pterodactyl, Wings, Docker va tizim paketlariga tegilmaydi.

---

## Muammolarni hal qilish

| Muammo | Yechim |
|---|---|
| `Servers N/A` + "run as root" | `sudo serverinfo` — Wings token va Docker socket faqat root uchun ochiq |
| `$'\r': command not found` | Fayllar Windows'da CRLF bilan saqlangan: `sed -i 's/\r$//' install.sh uninstall.sh serverinfo` |
| Ranglar noto'g'ri | `serverinfo --no-color` yoki terminalda `TERM=xterm-256color` |
| Harorat `N/A` | VPS'da sensor yo'q — bu normal holat |
| Public IP `N/A (private address / NAT)` | `serverinfo --public-ip` yoki konfiguratsiyada `PUBLIC_IP_LOOKUP=yes` |
| Online: `Download failed` / `not found` | Repo public ekanini, `--ref` to'g'riligini va tarmoqni tekshiring; xato tafsilotlari `/tmp/elitehost-serverinfo-install.*.log` da |
| `sudo bash <(curl ...)`: `/dev/fd/63: No such file` | `curl -fsSL <url> \| sudo bash` shaklidan foydalaning |
| `apt` o'rnata olmadi | Tarmoq/repo muammosi; `serverinfo` baribir ishlaydi, keyin `apt install curl jq iproute2 procps` |

---

## Fayl tuzilmasi

```text
elitehost-serverinfo/
├── install.sh      # online (bash <(curl ...)) + lokal o'rnatuvchi
├── uninstall.sh    # xavfsiz o'chiruvchi
├── serverinfo      # asosiy CLI utilita (/usr/local/bin/serverinfo)
├── README.md
└── LICENSE
```

O'rnatilgandan keyin:

```text
/usr/local/bin/serverinfo                                  # asosiy buyruq
/usr/local/lib/elitehost-serverinfo/uninstall.sh           # serverinfo --uninstall uchun
/etc/elitehost/serverinfo.conf                             # konfiguratsiya
/usr/local/share/bash-completion/completions/serverinfo    # Tab completion
```

---

## Litsenziya

MIT — [LICENSE](LICENSE) faylini ko'ring.

**EliteHost • Server Infrastructure**
