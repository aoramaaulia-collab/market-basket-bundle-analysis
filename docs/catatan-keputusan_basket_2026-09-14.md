# Catatan Keputusan: Analisis Keranjang Belanja (SQL-02)

**Analis:** Aulia Aorama · **Tanggal:** 14 September 2026
**Pemangku kepentingan:** Mbak Dian (Head of Product/Merchandising), ShopEase Indonesia
**Keputusan yang menunggu:** bundel mana yang dipasang untuk kampanye Ramadan berbiaya **Rp 80 juta**
**Alat:** SQL di **DuckDB** atas `order_items.csv` (cara kedua yang disediakan modul di halaman 01)
**Periode data:** 1 Januari 2025 sampai 31 Maret 2026, lima kuartal

Berkas ini adalah **satu-satunya sumber angka** untuk memo, lampiran bukti, dan portofolio. Setiap angka di ketiga berkas itu bisa dihasilkan ulang dari kueri di bagian 11 dan 12, dan keenam gambar di lampiran serta portofolio dibuat oleh notebook `SQL-02_Market_Basket_DuckDB.ipynb` dari kueri yang sama. Kalau ada angka yang berbeda, yang salah adalah berkas lainnya, bukan berkas ini.

---

## Daftar istilah

Supaya catatan ini bisa dibaca orang teknis maupun non-teknis:

| Istilah | Artinya dalam bahasa sehari-hari |
|---|---|
| **Keranjang** | Satu order. Isinya adalah daftar produk yang dibeli dalam order itu, masing-masing dihitung sekali. |
| **Support (keranjang penopang)** | Berapa keranjang yang memuat kedua produk sekaligus. Ini ukuran **seberapa besar** bisnis yang tersentuh. |
| **Confidence** | Dari keranjang yang memuat produk A, berapa persen yang juga memuat produk B. Angkanya bisa berbeda kalau arahnya dibalik. |
| **Lift (kali lipat dari kebetulan)** | Berapa kali lebih sering dua produk muncul bersama dibanding kalau keduanya sama sekali tidak berhubungan. Angka 1 berarti persis seperti kebetulan. |
| **Batas maksimum lift** | Lift tertinggi yang **mungkin** dicapai sebuah pasangan. Batas ini ditentukan oleh produk yang lebih populer di pasangan itu: makin populer, makin rendah batasnya. |
| **z** | Seberapa kecil kemungkinan sebuah pola hanya kebetulan. Di atas 1,96 lazim dianggap bukan kebetulan. |
| **Ambang bukti** | Jumlah keranjang minimum yang harus menopang sebuah pasangan sebelum ia boleh direkomendasikan. **Angka ini keputusan analis**, bukan hasil data. |
| **Ruang tumbuh** | Jumlah keranjang yang baru memuat **salah satu** produk bundel. Di situlah bundel bisa menambah produk kedua. |
| **K, R, B** | Nomor keputusan (K1 sampai K10), rekomendasi (R1 sampai R4), dan batas (B1 sampai B8). Nomor yang sama dipakai di semua berkas. |

---

## 1. Profil data dan definisi keranjang

### 1.1 Apa yang kotor dan apa yang terbukti bersih

Seluruh tujuh kolom diperiksa sebelum satu baris pun dibuang.

| Pemeriksaan | Hasil |
|---|---|
| Baris mentah | 18.815 baris, 3.000 order, 15 produk |
| `ProductID` kosong | **375 baris**, dan **seluruhnya masih punya `ProductName`** |
| Pemetaan nama produk ke `ProductID` | tepat 1 banding 1 (15 nama, 15 ID) |
| Kuantitas nol atau negatif | **200 baris**, semuanya negatif (tidak ada yang nol). Nilai kuantitas hanya -3 sampai 3 |
| Harga nol | **150 baris** |
| Kolom lain yang kosong | 0 baris di `OrderID`, `ProductName`, `Category`, `Quantity`, `Price`, `OrderDate` |
| Satu produk, satu kategori | ya, tanpa pengecualian |
| Satu order, satu tanggal | ya, tanpa pengecualian |
| Harga tiap produk | hanya bergerak paling jauh 5,2% dari harga tengahnya. Tidak ada harga janggal |
| Format `OrderID` dan `ProductID` | seluruhnya sah |

**Kesimpulannya: di luar empat jenis kotoran di bawah, data ini bersih.**

### 1.2 Pembersihan empat tahap

| Tahap | Membuang | Dibuang | Sisa |
|---|---|---:|---:|
| (mentah) | | | 18.815 |
| `deduped` | duplikat persis (ketujuh kolom identik) | 835 | 17.980 |
| `teridentifikasi` | `ProductID` kosong | 374 | 17.606 |
| `dibeli` | `Quantity` kurang dari atau sama dengan 0 (retur) | 200 | 17.406 |
| `bersih` | `Price` kurang dari atau sama dengan 0 (sampel gratis) | 147 | **17.259** |

Total dibuang **1.556 baris (8,3%)**, menyisakan **17.259 item dari 3.000 order**. Rata-rata tiap keranjang berisi **5,75 produk**, turun dari 6,3 baris per order di tabel mentah.

Alasan tiap pembuangan ada di keputusan **K1** (bagian 2). Dua catatan: penyebab pencatatan ganda **tidak diketahui dari data**, dan produk dengan `ProductID` kosong **masih bisa dikenali dari `ProductName`** (batas **B6**). Grafik kerja A di notebook memperlihatkan proporsinya.

### 1.3 Kenapa angka profil berbeda dari angka pipeline

Profil menghitung 375 `ProductID` kosong dan 150 harga nol, sedangkan pipeline membuang 374 dan 147. **Penyebab kedua selisih itu berbeda:**

- **375 menjadi 374:** satu baris `ProductID` kosong adalah duplikat, jadi sudah keluar di tahap pertama.
- **150 menjadi 147:** tidak ada satu pun baris harga nol yang duplikat. Selisih 3 itu adalah **3 baris yang sekaligus retur dan harga nol**, sehingga sudah keluar di tahap `Quantity`, sebelum tahap `Price`.

### 1.4 Batas pembuangan retur dan sampel gratis

Pembuangan dilakukan per baris, bukan per pembelian. Akibatnya ada tiga hal yang perlu dicatat apa adanya:

- **16 produk dibeli lalu dikembalikan penuh di order yang sama.** Baris returnya dibuang, tetapi baris pembeliannya tetap masuk keranjang. Jadi produk yang pembelinya sudah membatalkan tetap terhitung "dibeli bersama".
- **184 baris retur tidak punya pembelian produk yang sama di order itu.** Data tidak menyimpan kaitan antara retur dan pembelian asalnya, jadi pembelian asal itu tidak bisa ikut dibatalkan.
- **20 dari 150 baris sampel gratis adalah produk yang juga dibeli di order yang sama.** Membuang baris gratisnya tidak mengeluarkan produk itu dari keranjang.

Ini batas **B5**. **Dampaknya diuji di bagian 7:** keranjang dihitung ulang berdasarkan kuantitas neto (produk yang diretur penuh dikeluarkan). Hasilnya 17.243 baris, dan **tiga bundel yang sama tetap lolos dengan lift yang sama**.

### 1.5 Keranjang sebagai himpunan, dan seberapa besar duplikat menggandakan

Keranjang dibentuk dengan `SELECT DISTINCT OrderID, ProductID`. Di data ini langkah itu membuang **0 baris**, karena dedup tujuh kolom sudah menutup seluruh pengulangan. Langkah itu tetap dipertahankan sebagai **pagar** untuk data berikutnya.

Ini bukti untuk keputusan **K2**: di self-join, baris ganda **mengalikan**, bukan menambah. Ukurannya:

| Self-join dijalankan pada | Baris pasangan yang dihasilkan |
|---|---:|
| tabel mentah | 53.733 |
| tabel bersih tanpa dedup | 51.719 |
| keranjang bersih | **47.033** |

- **835 baris duplikat menghasilkan 4.686 pasangan semu (10,0%)**, rata-rata 5,6 pasangan semu untuk setiap baris duplikat.
- Penggandaan itu menimpa **729 order (24,3%)**, dengan median 6 pasangan semu per order dan paling banyak 30 di satu order. **Tidak merata**, sehingga urutan pasangan ikut bergeser.
- Sisa selisih dari tabel mentah (2.014 pasangan, 4,3%) berasal dari tiga kotoran lainnya.

Order besar memperbesar efek ini: order berisi 7 produk atau lebih hanya **33,1% dari jumlah order**, tetapi menyumbang **61,5% dari seluruh pasangan**, karena jumlah pasangan tumbuh kuadratik terhadap ukuran keranjang (grafik kerja B di notebook).

---

## 2. Keputusan analisis dan alasannya

Setiap keputusan di bawah diambil sebelum hasilnya dibaca, dan setiap keputusan punya pilihan lain yang ditolak berikut alasannya. Bukti angka untuk tiap keputusan ada di bagian 1, 3, 4, dan 7.

| No | Keputusan | Alasan | Yang ditolak, dan alasannya |
|---|---|---|---|
| K1 | **Empat jenis baris dibuang: duplikat persis, ProductID kosong, retur, dan sampel gratis.** | Pertanyaan bisnisnya adalah produk apa yang dipilih bersama dalam satu keputusan belanja. Keempat jenis baris itu bukan pilihan belanja: salinan, tanpa identitas produk, dibatalkan pembelinya, atau diberikan penjual. | Menghitung semua baris apa adanya, karena 835 duplikat saja menciptakan 4.686 pasangan palsu. |
| K2 | **Keranjang dibentuk sebagai himpunan produk unik per order.** | Yang ditanyakan adalah produk apa yang muncul bersama, bukan berapa banyak yang dibeli. Di self-join, baris ganda mengalikan hitungan pasangan, bukan menambah. | Keranjang dari daftar baris, karena satu kejadian belanja bisa terhitung berkali-kali. |
| K3 | **Seluruh pembersihan selesai sebelum self-join.** | Begitu pasangan terbentuk, asal barisnya hilang. Tidak ada cara lagi untuk menyaring pasangan yang berasal dari retur atau sampel gratis. | Membersihkan sesudah keranjang dibentuk. |
| K4 | **Support, confidence dua arah, dan lift ditampilkan berdampingan, selalu dengan jumlah keranjang di sebelah rasionya.** | Tiap metrik buta terhadap hal yang berbeda: support tidak tahu apakah hubungannya nyata, lift dan confidence tidak tahu seberapa besar buktinya. | Mengurutkan dengan satu metrik lalu mengambil sepuluh teratas, karena support menaikkan dua pasangan laris yang berlift 0,99 dan 1,00, sedangkan lift menaikkan pasangan yang hanya ada di 146 keranjang. |
| K5 | **Kekuatan hubungan dibandingkan terhadap batas maksimumnya.** | Lift tertinggi yang mungkin dicapai sebuah pasangan ditentukan oleh produk yang lebih populer. Lift dan batasnya bergerak bersama di seluruh 105 pasangan (korelasi 0,91), jadi lift pasangan produk jarang tidak bisa dibandingkan langsung dengan pasangan produk laris. | Membaca lift 13,46 sebagai "delapan kali lebih kuat" dari bundel terbaik. |
| K6 | **Uji kebetulan memakai z dengan galat baku binomial.** | Peluang kemunculan bersama ketiga bundel sekitar 20% sampai 30%, terlalu besar untuk rumus Poisson yang dibuat untuk peluang kecil. Rumus binomial juga yang mereproduksi nilai z di modul halaman 07. | Rumus Poisson. Daftar yang lolos tetap sama, karena z tertinggi di antara pasangan yang tidak lolos hanya 1,36. |
| K7 | **Ambang bukti 200 keranjang.** | Tiap bundel memakan porsi anggaran yang sama besar entah berhasil atau tidak, jadi bundel berjangkauan kecil membayar harga penuh. Hasilnya tidak berubah untuk ambang mana pun antara 200 dan 1.200. | Ambang berbentuk persentase (jumlah keranjang lebih mudah diterjemahkan ke jangkauan kampanye) dan ambang yang disembunyikan di LIMIT 10. |
| K8 | **Saringan memakai tiga syarat sekaligus: lift di atas 1, minimal 200 keranjang, dan z di atas 1,96.** | Tiap syarat menutup lubang yang ditinggalkan dua lainnya: pasangan laris tanpa hubungan, hubungan nyata yang terlalu kecil, dan lift di atas 1 yang lahir dari kebetulan. | Menyaring dengan lift di atas 1 saja, karena 47 dari 105 pasangan lolos, kira-kira separuh, persis yang diharapkan kalau tidak ada hubungan sama sekali. |
| K9 | **Lintas kategori dilaporkan sebagai kolom, bukan dipakai sebagai saringan.** | Dua dari tiga bundel yang layak justru satu kategori. | Menyaring hanya pasangan lintas kategori, karena akan membuang dua bundel yang layak. |
| K10 | **Pada potongan enam bulan, ambang diturunkan sebanding menjadi 81 keranjang.** | Keranjangnya tinggal 1.218 (40,6%). Memakai 200 apa adanya berarti menaikkan syaratnya diam-diam. | Memakai ambang 200 apa adanya pada potongan yang lebih kecil. |

---

## 3. Metrik

Ketiga metrik dihitung dan **ditampilkan berdampingan**, selalu dengan jumlah keranjang di sebelahnya.

| Metrik | Menjawab | Buta terhadap |
|---|---|---|
| Support | Seberapa besar bisnis yang tersentuh | Apakah hubungannya nyata |
| Confidence (dua arah) | Kalau A dibeli, seberapa sering B ikut | Besar basisnya; dan arahnya tidak simetris |
| Lift | Seberapa jauh dari kebetulan | Besar basisnya; dan **batas maksimumnya berbeda untuk tiap pasangan** |
| z | Seberapa kecil kemungkinan pola ini kebetulan | **Tidak mengukur jangkauan.** z tinggi bisa lahir dari lift besar pada basis kecil |

**Batas maksimum lift.** Lift sebuah pasangan tidak bisa melebihi jumlah keranjang dibagi jumlah keranjang produk yang lebih populer. Pasangan dari produk laris punya batas rendah; pasangan dari produk jarang punya batas tinggi. Di seluruh 105 pasangan, lift dan batasnya bergerak bersama (korelasi 0,91). Karena itu **lift dua pasangan dengan popularitas berbeda tidak bisa dibandingkan langsung.** Lift dibagi batasnya sama dengan confidence dari arah produk yang lebih jarang, sehingga perbandingan yang adil bisa dibaca dari angka itu.

**Rumus z yang dipakai:** galat baku binomial,
`(bersama − harapan) / akar(n · p · (1 − p))`, dengan `p = support_a × support_b` dan `harapan = n · p`.

**Bukti untuk keputusan K6.** Rumus Poisson (`/ akar(harapan)`) cocok untuk peluang yang sangat kecil, sedangkan di sini peluang kemunculan bersama ketiga bundel sekitar 20% sampai 30%. Poisson menghasilkan z 18,4 · 14,3 · 12,8 untuk ketiga bundel, binomial 21,1 · 17,1 · 15,6. **Daftar yang lolos sama persis** dengan kedua rumus, karena z tertinggi di antara pasangan yang tidak lolos hanya 1,36, jauh di bawah 1,96. Rumus binomial juga yang mereproduksi nilai z di modul halaman 07.

**Bukti untuk keputusan K4** (Gambar 6 di notebook dan portofolio). Diurutkan dengan support, peringkat empat dan lima adalah Daily Moisturizer + Eye Cream (1.066 keranjang, lift 0,99) dan Brightening Serum + Daily Moisturizer (976, lift 1,00): dua pasangan produk terlaris yang muncul bersama persis sesering kebetulan. Diurutkan dengan lift, puncaknya pasangan dengan bukti paling tipis.

**Kenapa confidence ditampilkan dua arah.** Untuk Daily Moisturizer + Sunscreen SPF50, arahnya 74,6% lawan 87,6%. Selisih itu menunjukkan produk mana yang lebih sering "menarik" pasangannya, dan dipakai untuk memutuskan bundel dipajang di halaman produk yang mana (grafik kerja D di notebook).

---

## 4. Ambang dan susunan saringan (keputusan K7 dan K8)

```
lift > 1              lebih sering daripada kebetulan
bersama >= 200        cukup besar untuk dikampanyekan
z > 1,96              tidak bisa dijelaskan kebetulan
```

**Ambang 200 keranjang** (keputusan K7) dipilih karena **tiap bundel memakan porsi anggaran yang sama besar entah ia berhasil atau tidak**: materi visual, tempat di halaman depan, dan potongan harga dibayar per bundel. Bundel yang salah pilih memakan biaya penuh.

**Rentang stabil: hasilnya sama untuk ambang mana pun antara 200 dan 1.200 keranjang.** Batas persisnya 147 sampai 1.231: di bawah 147 pasangan yang ditolak ikut lolos, di atas 1.231 Matte Lip Cream + Lip Liner ikut terbuang.

Efek tiap syarat, diterapkan berurutan:

| Saringan | Lolos | Yang tersingkir |
|---|---:|---|
| (semua pasangan) | 105 | |
| lift > 1 | 47 | 58 pasangan berlift 1 atau kurang |
| + bersama >= 200 | 34 | 13 pasangan bervolume kecil, termasuk pasangan yang ditolak |
| + z > 1,96 | **3** | 31 pasangan yang lift-nya di atas 1 semata karena kebetulan |

Ambang bekerja sangat berbeda tergantung apa yang menemaninya (lampiran Gambar 5):

| Ambang | lift > 1 saja | Ketiga syarat | Pasangan yang ditolak ikut lolos? |
|---:|---:|---:|---|
| minimal 0 | 47 | 4 | ya |
| minimal 100 | 37 | 4 | ya |
| minimal 146 | 35 | 4 | ya |
| minimal 147 | 34 | 3 | tidak |
| minimal 200 | 34 | 3 | tidak |
| minimal 800 | 4 | 3 | tidak |
| minimal 1.200 | 3 | 3 | tidak |
| minimal 1.231 | 3 | 3 | tidak |
| minimal 1.232 | 2 | 2 | tidak |
| minimal 1.300 | 2 | 2 | tidak |

---

## 5. Hasil: tiga bundel dan pasangan yang ditolak

### 5.1 Tiga bundel yang lolos (lampiran Gambar 1 dan 2)

Dari 3.000 keranjang dan 105 pasangan, tersisa tiga:

| Bundel | Kategori | Keranjang | % keranjang | Lift | Batas lift | % dari batas | z | Conf A ke B | Conf B ke A | Ruang tumbuh |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Matte Lip Cream + Lip Liner | Lip Care + Lip Care | 1.231 | 41,0% | 1,68 | 1,95 | 86,0% | 21,1 | 86,0% | 80,1% | 507 |
| Brightening Serum + Eye Cream | Face Care + Eye Care | 1.333 | 44,4% | 1,48 | 1,74 | 84,7% | 17,1 | 84,7% | 77,4% | 630 |
| Daily Moisturizer + Sunscreen SPF50 | Face Care + Face Care | 1.395 | 46,5% | 1,41 | 1,61 | 87,6% | 15,6 | 74,6% | 87,6% | 672 |

*Ruang tumbuh* = jumlah keranjang yang **baru memuat salah satu** dari kedua produk. Di sinilah bundel punya kesempatan menambah produk kedua.

- **Jangkauan:** ketiganya ditopang **1.231 sampai 1.395 dari 3.000 keranjang** (41% sampai 46% keranjang).
- **Kekuatan:** ketiganya muncul bersama **1,41 sampai 1,68 kali lebih sering** daripada kebetulan, dengan z 15,6 sampai 21,1.
- **Alasan pemakaian** yang bisa diucapkan tanpa angka: lip cream dan lip liner dipakai berurutan dalam satu rutinitas; pelembap dan tabir surya adalah dua langkah pagi yang berturutan; serum pencerah dan krim mata sama-sama dibeli orang yang sedang serius merawat wajahnya.
- **Satu bundel menghubungkan dua kategori:** Brightening Serum (Face Care) dengan Eye Cream (Eye Care). Apakah bundel itu benar-benar memindahkan pembeli ke kategori lain **belum diketahui**; justru itu yang diukur oleh uji kelompok pembanding.

Keputusan mana yang diuji lebih dulu kalau anggaran terbatas ada di rekomendasi **R4** (bagian 8).

### 5.2 Pasangan yang ditolak (lampiran Gambar 1 dan 2)

**Eye Primer + Eyeliner Pen:** 146 dari 3.000 keranjang (4,9%), lift 13,46, z 41,1.

- **Hubungannya nyata.** Nilai z-nya tertinggi di seluruh tabel. Uji kebetulan tidak akan pernah menyingkirkannya.
- **Confidence-nya hanya tinggi dari satu arah:** 92,4% keranjang yang memuat Eye Primer juga memuat Eyeliner Pen, tetapi hanya **70,9%** keranjang yang memuat Eyeliner Pen juga memuat Eye Primer.
- **Lift-nya tampak 8 kali lipat bundel terbaik, tetapi itu karena batas maksimumnya jauh lebih tinggi.** Kedua produknya paling jarang dari lima belas (Eye Primer 158 keranjang, Eyeliner Pen 206 keranjang), sehingga batas lift pasangan ini 14,56, sedangkan batas ketiga bundel hanya 1,61 sampai 1,95, atau 7,5 sampai 9,1 kali lebih rendah. **Diukur terhadap batasnya, keempat pasangan sama kuat: 84,7% sampai 92,4%**, selisih hanya 4,8 poin dari bundel terkuat. Di gambar sebar, 101 pasangan lainnya menumpuk di sekitar garis kebetulan.
- **Produk terjarang berikutnya** (Eyebrow Pencil) ada di 786 keranjang, 3,8 kali lebih banyak. Kedua produk ini berada di kelas yang berbeda dari tiga belas produk lainnya (grafik kerja C di notebook).

Apa yang dilakukan terhadap pasangan ini, dan alasannya, ada di rekomendasi **R3** (bagian 8).

---

## 6. Variasi: enam bulan terakhir

Pertanyaan Mbak Dian: kalau analisis dibatasi pada order sejak 1 Oktober 2025, apakah rekomendasinya berubah?

Penyaring tanggal dipasang di **tahap paling awal**, sebelum keranjang dibentuk, karena keranjang yang sudah jadi tidak lagi menyimpan tanggal.

| | Lima kuartal | Enam bulan |
|---|---:|---:|
| Baris mentah | 18.815 | 7.836 |
| Item bersih | 17.259 | 7.172 |
| Keranjang | 3.000 | 1.218 (40,6%) |
| Ambang bukti | 200 | **81** |
| Pasangan lift > 1 | 47 | 56 |
| Bundel lolos | 3 | 3 |

**Ambang diturunkan sebanding:** 200 × 1.218 ÷ 3.000 = 81 keranjang. Memakai 200 apa adanya pada keranjang yang tinggal 40,6% berarti menaikkan syaratnya diam-diam.

| Bundel | Keranjang 6 bln | % keranjang 6 bln | % keranjang penuh | Lift 6 bln | Lift penuh | z 6 bln |
|---|---:|---:|---:|---:|---:|---:|
| Matte Lip Cream + Lip Liner | 515 | 42,3% | 41,0% | 1,64 | 1,68 | 13,1 |
| Brightening Serum + Eye Cream | 552 | 45,3% | 44,4% | 1,47 | 1,48 | 10,9 |
| Daily Moisturizer + Sunscreen SPF50 | 577 | 47,4% | 46,5% | 1,37 | 1,41 | 9,3 |
| *Eye Primer + Eyeliner Pen (ditolak)* | *56* | *4,6%* | *4,9%* | *13,64* | *13,46* | |

**Apakah rekomendasinya berubah? Tidak.** Bundel yang sama, urutan yang sama, dan pasangan yang ditolak tetap di luar (56 keranjang, di bawah ambang 81).

**Apa artinya bagi keyakinan pada daftar ini:**

- **Porsi keranjang ketiga bundel naik tipis** di jendela yang lebih dekat ke kampanye (41,0% ke 42,3%, 44,4% ke 45,3%, 46,5% ke 47,4%).
- **Lift ketiganya turun tipis** (1,68 ke 1,64, 1,48 ke 1,47, 1,41 ke 1,37). Nilai z juga lebih kecil, wajar karena keranjangnya lebih sedikit, tetapi masih jauh di atas 1,96.
- **Kedua gerakan itu kecil dan tidak mengubah daftar.** Kampanye bulan depan tidak sedang dibangun dari perilaku lama yang sudah berubah.
- **Pasangan berlift di atas 1 naik dari 47 menjadi 56.** Derau membesar ketika jumlah keranjang mengecil, dan itu justru alasan syarat z tidak boleh dilepas di potongan mana pun.
- Rentang ambang yang hasilnya stabil di potongan ini: 57 sampai 515 keranjang.

**Dugaan sebelum menghitung, ditulis apa adanya:** saya memperkirakan ketiga bundel bertahan dan lift pasangan yang ditolak turun karena periodenya dipendekkan. Bagian pertama tepat; bagian kedua meleset, lift-nya justru naik tipis ke 13,64. Ini memperkuat penolakan: pasangan itu **stabil dan tetap tipis**, bukan korban periode yang salah.

---

## 7. Uji kepekaan dan bantahan

### 7.1 Dua belas cara menghitung ulang (lampiran Gambar 4)

| Cara menghitung | Ambang | Bundel yang lolos | Keranjang pasangan yang ditolak |
|---|---:|---|---:|
| Data penuh (dasar) | 200 | tiga bundel yang sama | 146 |
| Enam bulan terakhir | 81 | tiga bundel yang sama | 56 |
| K1 2025 | 37 | tiga bundel yang sama | 27 |
| K2 2025 | 41 | tiga bundel yang sama | 33 |
| K3 2025 | 41 | tiga bundel yang sama | 30 |
| K4 2025 | 42 | tiga bundel yang sama | 21 |
| K1 2026 | 40 | tiga bundel yang sama | 35 |
| ProductID dipulihkan dari nama produk | 200 | tiga bundel yang sama | 152 |
| Retur dibiarkan | 200 | tiga bundel yang sama | 147 |
| Sampel gratis dibiarkan | 200 | tiga bundel yang sama | 151 |
| Retur dan sampel dibiarkan | 200 | tiga bundel yang sama | 152 |
| Keranjang neto (retur penuh keluar) | 200 | tiga bundel yang sama | 146 |

**Di kedua belas cara itu, tiga bundel yang sama lolos dan pasangan yang ditolak tetap di bawah ambang.** Tiap kuartal berisi 551 sampai 625 keranjang dengan ambang 37 sampai 42 keranjang (200 dikali porsi keranjang kuartal itu), sedangkan pasangan yang ditolak hanya 21 sampai 35 keranjang. Lift tiap bundel antar-kuartal bergerak paling lebar 0,18.

Ringkasan kepekaan:

| Asumsi yang digeser | Akibat pada tiga bundel |
|---|---|
| Ambang 200 menjadi mana pun antara 200 dan 1.200 | Tidak berubah |
| Ambang di bawah 147 | Pasangan yang ditolak ikut lolos; tiga bundel tetap |
| Ambang di atas 1.231 | Satu bundel terbuang |
| Syarat z dilepas | Daftar melonjak dari 3 menjadi 34 |
| Periode enam bulan atau per kuartal | Tidak berubah |
| Keempat keputusan pembersihan dibalik | Tidak berubah |

**Bacaannya: rekomendasi ini kokoh terhadap ambang, periode, dan cara membersihkan data. Satu-satunya titik rapuhnya adalah syarat z.** Di situlah perdebatan sesungguhnya akan terjadi.

### 7.2 Bantahan dan jawabannya

**Bantahan 1: "Keduanya memang laris, wajar kalau sering berbarengan."**
Benar sebagai mekanisme, dan memang terjadi di data ini: Daily Moisturizer + Eye Cream (1.066 keranjang) dan Brightening Serum + Daily Moisturizer (976) berlift 0,99 dan 1,00. Jawabannya: **lift sudah memperhitungkan popularitas**, dan ketiga bundel ada di 1,41 sampai 1,68. *Yang akan membatalkan jawaban ini:* lift yang mendekati 1. Tidak ada.

**Bantahan 2: "Bundel lintas kategori cuma efek keranjang yang besar."** (lampiran Gambar 3)
Kalau benar, seluruh pasangan lintas kategori akan ikut terangkat. Hasilnya:

| | Lintas kategori | Satu kategori |
|---|---:|---:|
| Jumlah pasangan | 75 | 30 |
| Lift median | 0,995 | 0,999 |
| Lift rata-rata | 1,004 | 1,442 |
| Lift rata-rata tanpa pasangan yang ditolak | 1,004 | 1,027 |
| Lift di atas 1 | 33 (44%) | 14 (47%) |
| Hubungan nyata (lift > 1 dan z > 1,96) | **1** | **3** (1 di antaranya ditolak) |

**Pasangan biasa di kedua kelompok sama-sama duduk di garis kebetulan** (median sekitar 1,00). Pasangan lintas kategori tidak terangkat merata; hanya satu yang menonjol, yaitu bundel yang diusulkan. Bantahan ini gugur.

*Catatan koreksi:* versi sebelumnya membandingkan rata-rata 1,004 lawan 1,442 dan menyimpulkan "asosiasi hampir seluruhnya terjadi di dalam kategori". **Angka 1,442 ditarik oleh satu pencilan** (pasangan yang ditolak, lift 13,46). Tanpa pasangan itu, rata-ratanya 1,027. Kesimpulan yang benar: hubungan nyata lebih sering di dalam kategori (3 dari 30) daripada lintas kategori (1 dari 75), tetapi pasangan tipikal di kedua kelompok sama-sama kebetulan.

**Bantahan 3: "z-nya tertinggi, kenapa justru dibuang?"**
Benar seluruhnya. Hubungannya nyata, dan diukur terhadap batas maksimumnya sama kuat dengan ketiga bundel. Yang berbeda adalah **jangkauannya: 146 dari 3.000 keranjang.** Lihat bagian 5.2 dan rekomendasi R3.

**Bantahan yang tidak punya jawaban: "Kalau orang sudah membelinya bersama tanpa diskon, kenapa kita mendiskonnya?"**
Bantahan ini benar dan menyerang dasar seluruh analisis keranjang. **Data ini hanya menunjukkan apa yang sudah dibeli bersama, bukan apa yang akan dibeli kalau didorong**, karena tidak ada satu pun percobaan promosi di dalamnya. Karena itu bentuk rekomendasinya diubah: ketiga bundel diusulkan sebagai **kandidat uji dengan kelompok pembanding** (sebagian pembeli melihat bundel, sebagian tidak), bukan keputusan final. Kalau selisihnya nol, itu diketahui setelah menghabiskan sebagian kecil anggaran, bukan seluruhnya.

---

## 8. Rekomendasi dan alasannya

| No | Rekomendasi | Alasan |
|---|---|---|
| R1 | **Pasang tiga bundel: Matte Lip Cream + Lip Liner, Brightening Serum + Eye Cream, dan Daily Moisturizer + Sunscreen SPF50.** | Hanya ketiganya yang lolos ketiga syarat dari 105 pasangan. Jangkauannya 1.231 sampai 1.395 dari 3.000 keranjang, kekuatannya 1,41 sampai 1,68 kali lipat dari kebetulan, dan hasilnya sama di dua belas cara menghitung ulang. Ketiganya juga masuk akal secara pemakaian: kedua produknya dipakai dalam rutinitas perawatan yang sama. |
| R2 | **Jalankan ketiganya sebagai uji dengan kelompok pembanding, bukan langsung penuh: sebagian pembeli melihat bundel, sebagian tidak.** | Data hanya menunjukkan apa yang sudah dibeli bersama, bukan apa yang akan dibeli karena dibundel. Tanpa kelompok pembanding, kenaikan penjualan tidak bisa dibedakan dari pembelian yang memang sudah terjadi. Kalau selisihnya nol, itu diketahui setelah menghabiskan sebagian kecil anggaran, bukan seluruhnya. |
| R3 | **Jangan kampanyekan Eye Primer + Eyeliner Pen; pasang di rekomendasi otomatis halaman produk.** | Hubungannya nyata dan, diukur terhadap batas maksimumnya, sama kuat dengan ketiga bundel (92,4% lawan 84,7% sampai 87,6%). Tetapi ia hanya menyentuh 146 dari 3.000 keranjang, kurang dari seperdelapan bundel terkecil, dengan biaya kampanye yang sama. Di kanal yang biayanya nyaris nol per pasangan, hubungan kuat pada kelompok kecil justru berguna. |
| R4 | **Kalau anggaran hanya cukup untuk dua uji: jalankan Brightening Serum + Eye Cream dan Daily Moisturizer + Sunscreen SPF50, tunda Matte Lip Cream + Lip Liner.** | Matte Lip Cream + Lip Liner punya ruang tumbuh paling kecil: hanya 507 keranjang yang baru memuat salah satu produknya, dibanding 630 dan 672. Diskonnya paling mungkin hanya membiayai pembelian yang sudah terjadi. Brightening Serum + Eye Cream didahulukan karena ia satu-satunya hubungan nyata di antara 75 pasangan lintas kategori, sehingga hasil ujinya paling sedikit bisa ditebak dari pasangan lain. |

---

## 9. Batas dan alasannya

| No | Batas | Kenapa ini batas | Akibatnya, dan yang dilakukan |
|---|---|---|---|
| B1 | **Penjualan tambahan dari bundel tidak bisa diperkirakan.** | Data tidak memuat hasil kampanye maupun percobaan promosi apa pun. | Tidak ada klaim kenaikan penjualan, uplift, conversion, atau ROI, termasuk klaim bahwa bundel lintas kategori memindahkan pembeli ke kategori baru. Rekomendasi dibuat berbentuk uji (R2). |
| B2 | **Semua persentase adalah persentase keranjang, bukan persentase orang.** | Data tidak punya ID pelanggan, dan satu orang bisa punya banyak order. | Setiap angka ditulis bersama penyebutnya, misalnya "dari 3.000 keranjang". |
| B3 | **Margin bundel tidak dinilai.** | Harga pokok tidak ada di data. | Bundel yang masuk akal secara perilaku bisa saja rugi setelah diskon. Besaran diskon perlu dihitung tim keuangan sebelum uji dijalankan. |
| B4 | **Ambang bukti 200 keranjang adalah keputusan analis, bukan sifat data.** | Angka itu tidak berasal dari data maupun dari pemangku kepentingan. | Ambangnya dinyatakan dan diuji: hasilnya tidak berubah untuk ambang mana pun antara 200 dan 1.200. |
| B5 | **Pembuangan retur tidak membatalkan semua pembelian yang diretur.** | 16 produk dibeli lalu dikembalikan penuh di order yang sama tetapi baris pembeliannya tetap terhitung, dan 184 retur tidak tertaut ke pembelian asalnya. | Diuji dengan keranjang berbasis kuantitas neto: tiga bundel yang sama tetap lolos. |
| B6 | **375 baris ProductID kosong dibuang, padahal produknya bisa dikenali dari nama.** | Dibuang supaya hasil cocok dengan gerbang angka modul. | Diuji dengan ProductID dipulihkan dari nama produk: tiga bundel yang sama tetap lolos. |
| B7 | **Alasan orang membeli dan produk yang tidak jadi dibeli tidak terlihat.** | Data hanya memuat transaksi yang selesai. | Alasan pemakaian tiap bundel adalah tafsiran yang masuk akal, bukan temuan data. |
| B8 | **Hasil ini bergantung pada syarat z.** | Tanpa syarat z, daftar melonjak dari 3 menjadi 34 pasangan, sebagian besar derau. | Syarat z dipertahankan di setiap potongan data, termasuk potongan enam bulan dan per kuartal. |

**Apa yang akan membatalkan rekomendasi ini:** Uji kelompok pembanding yang menunjukkan selisih nol antara pembeli yang melihat bundel dan yang tidak. Satu pertanyaan tidak bisa dijawab dari data ini: kalau orang sudah membeli kedua produk bersama tanpa diskon, bundelnya mungkin hanya membiayai pembelian yang memang sudah terjadi. Uji kelompok pembanding dirancang tepat untuk menjawab itu.

---

## 10. Pemeriksaan aritmetika

| Pemeriksaan | Harus | Hasil |
|---|---|---|
| Jumlah pasangan | 105 | 105 (210 berarti tanda `<>` dipakai, bukan `<`) |
| Keranjang pasangan tidak melebihi keranjang tiap produknya | 0 pelanggaran | 0 |
| Confidence di atas 100% | 0 | 0 |
| Penyebut konsisten (keranjang = order bersih) | sama | 3.000 = 3.000 |
| Identitas lift = confidence ÷ support produk B | 0 | sekitar 0 (galat pembulatan komputer) |
| Rentang lift | | 0,89 sampai 13,46 |

---

## 11. Kueri final utuh

Dijalankan apa adanya di DuckDB dan menghasilkan ketiga bundel di bagian 5.1. Langkah pertama memuat data:

```sql
-- Muat data (DuckDB). Sesuaikan path berkasnya.
CREATE OR REPLACE TABLE order_items AS
SELECT * FROM read_csv_auto('order_items.csv');
```

```sql
-- ============================================================
-- KUERI FINAL: dari tabel mentah sampai tiga bundel
-- Keranjang = himpunan produk unik per order, dari item yang sah
-- ============================================================
WITH
-- TAHAP 1: pembersihan, empat tahap berurutan
deduped AS (                       -- 18.815 -> 17.980
    SELECT DISTINCT OrderID, ProductID, ProductName, Category,
           Quantity, Price, OrderDate
    FROM order_items
),
teridentifikasi AS (               -- 17.980 -> 17.606
    SELECT * FROM deduped WHERE ProductID IS NOT NULL AND ProductID <> ''
),
dibeli AS (                        -- 17.606 -> 17.406
    SELECT * FROM teridentifikasi WHERE Quantity > 0
),
bersih AS (                        -- 17.406 -> 17.259
    SELECT * FROM dibeli WHERE Price > 0
),

-- TAHAP 2: keranjang sebagai HIMPUNAN produk per order
keranjang AS (
    SELECT DISTINCT OrderID, ProductID FROM bersih
),
total AS (
    SELECT count(DISTINCT OrderID)::DOUBLE AS n FROM keranjang     -- 3.000
),
support_produk AS (
    SELECT ProductID, count(*)::DOUBLE AS order_produk
    FROM keranjang GROUP BY ProductID                               -- 15 baris
),

-- TAHAP 3: pasangan lewat self-join; tanda '<' bukan '<>'
pasangan AS (
    SELECT a.ProductID AS pa, b.ProductID AS pb, count(*)::DOUBLE AS bersama
    FROM keranjang AS a
    INNER JOIN keranjang AS b ON a.OrderID = b.OrderID
    WHERE a.ProductID < b.ProductID
    GROUP BY pa, pb                                                 -- 105 baris
),

-- TAHAP 4: metrik berdampingan
metrik AS (
    SELECT
        p.pa, p.pb,
        CAST(p.bersama AS BIGINT)                         AS support_order,
        p.bersama / t.n                                   AS support,
        p.bersama / sa.order_produk                       AS conf_a_ke_b,
        p.bersama / sb.order_produk                       AS conf_b_ke_a,
        p.bersama * t.n / (sa.order_produk * sb.order_produk) AS lift,
        t.n / greatest(sa.order_produk, sb.order_produk)  AS batas_lift,
        sa.order_produk + sb.order_produk - 2 * p.bersama AS ruang_tumbuh,
        -- z: jarak dari kebetulan dalam satuan simpangan baku (binomial)
        (p.bersama - sa.order_produk * sb.order_produk / t.n)
          / sqrt(t.n * (sa.order_produk / t.n) * (sb.order_produk / t.n)
                     * (1 - (sa.order_produk / t.n) * (sb.order_produk / t.n))) AS z
    FROM pasangan p
    CROSS JOIN total t
    INNER JOIN support_produk sa ON sa.ProductID = p.pa
    INNER JOIN support_produk sb ON sb.ProductID = p.pb
),
nama AS (
    SELECT DISTINCT ProductID, ProductName, Category FROM bersih
)

-- TAHAP 5: saringan tiga syarat; ambang terlihat, bukan di LIMIT
SELECT
    na.ProductName AS produk_a, na.Category AS kategori_a,
    nb.ProductName AS produk_b, nb.Category AS kategori_b,
    m.support_order,                                   -- penyebut, di sebelah rasionya
    round(m.support * 100, 1)       AS persen_keranjang,
    round(m.conf_a_ke_b * 100, 1)   AS conf_a_ke_b_pct,
    round(m.conf_b_ke_a * 100, 1)   AS conf_b_ke_a_pct,
    round(m.lift, 2)                AS lift,
    round(m.batas_lift, 2)          AS batas_lift,
    round(m.lift / m.batas_lift * 100, 1) AS persen_dari_batas,
    round(m.z, 1)                   AS z,
    m.ruang_tumbuh,
    (na.Category <> nb.Category)    AS lintas_kategori  -- KOLOM, bukan saringan
FROM metrik m
JOIN nama na ON na.ProductID = m.pa
JOIN nama nb ON nb.ProductID = m.pb
WHERE m.lift > 1
  AND m.support_order >= 200
  AND m.z > 1.96
ORDER BY m.lift DESC;
```

**Variasi enam bulan:** sisipkan `WHERE OrderDate >= DATE '2025-10-01'` di dalam CTE `deduped`, lalu ganti `>= 200` menjadi `>= 81`. Tidak ada bagian lain yang berubah. Versi lengkapnya ada di bagian 12.6.

---

## 12. Kueri pendukung: asal setiap angka

Blok pertama membuat tabel kerja dan satu fungsi bantu, supaya setiap blok sesudahnya **bisa dijalankan sendiri-sendiri**. Jalankan blok 12.0 sekali, lalu blok lain dalam urutan bebas (blok 12.6 sampai 12.8 membuat tabel tambahannya sendiri).

### 12.0 Tabel kerja dan fungsi bantu
```sql
-- Tabel kerja: supaya setiap pemeriksaan di bawah bisa dijalankan sendiri-sendiri
CREATE OR REPLACE TABLE deduped AS
    SELECT DISTINCT OrderID, ProductID, ProductName, Category, Quantity, Price, OrderDate
    FROM order_items;
CREATE OR REPLACE TABLE teridentifikasi AS
    SELECT * FROM deduped WHERE ProductID IS NOT NULL AND ProductID <> '';
CREATE OR REPLACE TABLE dibeli AS SELECT * FROM teridentifikasi WHERE Quantity > 0;
CREATE OR REPLACE TABLE bersih AS SELECT * FROM dibeli WHERE Price > 0;
CREATE OR REPLACE TABLE keranjang AS SELECT DISTINCT OrderID, ProductID FROM bersih;

-- Fungsi bantu: menghitung seluruh metrik untuk tabel keranjang mana pun
CREATE OR REPLACE MACRO asosiasi(k) AS TABLE
WITH t AS (SELECT count(DISTINCT OrderID)::DOUBLE AS n FROM query_table(k)),
sp AS (SELECT ProductID, count(*)::DOUBLE AS op FROM query_table(k) GROUP BY 1),
p AS (
    SELECT a.ProductID AS pa, b.ProductID AS pb, count(*)::DOUBLE AS bersama
    FROM query_table(k) a JOIN query_table(k) b ON a.OrderID = b.OrderID
    WHERE a.ProductID < b.ProductID GROUP BY 1, 2
)
SELECT p.pa, p.pb, CAST(p.bersama AS BIGINT) AS bersama, t.n,
       sa.op AS order_a, sb.op AS order_b,
       p.bersama / sa.op AS conf_a_ke_b, p.bersama / sb.op AS conf_b_ke_a,
       p.bersama * t.n / (sa.op * sb.op) AS lift,
       t.n / greatest(sa.op, sb.op) AS batas_lift,
       sa.op + sb.op - 2 * p.bersama AS ruang_tumbuh,
       (p.bersama - sa.op * sb.op / t.n)
         / sqrt(t.n * (sa.op / t.n) * (sb.op / t.n) * (1 - (sa.op / t.n) * (sb.op / t.n))) AS z
FROM p CROSS JOIN t
JOIN sp sa ON sa.ProductID = p.pa
JOIN sp sb ON sb.ProductID = p.pb;

CREATE OR REPLACE TABLE metrik AS SELECT * FROM asosiasi('keranjang');
```

### 12.1 Log pembersihan
```sql
-- Log pembersihan: lima angka sisa dan empat angka dibuang
SELECT
    (SELECT count(*) FROM order_items)     AS mentah,          -- 18.815
    (SELECT count(*) FROM deduped)         AS setelah_dedup,   -- 17.980
    (SELECT count(*) FROM teridentifikasi) AS setelah_pid,     -- 17.606
    (SELECT count(*) FROM dibeli)          AS setelah_qty,     -- 17.406
    (SELECT count(*) FROM bersih)          AS bersih,          -- 17.259
    (SELECT count(*) FROM keranjang)       AS baris_keranjang, -- 17.259 (DISTINCT keranjang membuang 0)
    (SELECT count(DISTINCT OrderID) FROM keranjang) AS keranjang; -- 3.000
```

### 12.2 Pemeriksaan aritmetika
```sql
-- Pemeriksaan aritmetika, dijalankan sebelum hasil ditafsirkan
SELECT
    (SELECT count(*) FROM metrik)                                         AS jumlah_pasangan,     -- 105, bukan 210
    (SELECT count(*) FROM metrik WHERE bersama > order_a OR bersama > order_b) AS lewat_batas_atas, -- 0
    (SELECT count(*) FROM metrik WHERE conf_a_ke_b > 1 OR conf_b_ke_a > 1)     AS conf_lebih_100,   -- 0
    (SELECT count(DISTINCT OrderID) FROM keranjang)                       AS penyebut_support,    -- 3.000
    (SELECT count(DISTINCT OrderID) FROM bersih)                          AS order_bersih,        -- 3.000
    (SELECT max(abs(lift - conf_a_ke_b / (order_b / n))) FROM metrik)     AS cek_identitas_lift,  -- ~0
    (SELECT round(min(lift), 2) FROM metrik)                              AS lift_terendah,       -- 0,89
    (SELECT round(max(lift), 2) FROM metrik)                              AS lift_tertinggi;      -- 13,46
```

### 12.3 Profil kolom dan selisih profil lawan pipeline
```sql
-- Profil seluruh kolom: apa yang kotor, apa yang terbukti bersih
SELECT
    count(*) FILTER (WHERE ProductID IS NULL OR ProductID = '')              AS productid_kosong,      -- 375
    count(*) FILTER (WHERE ProductID IS NULL AND ProductName IS NOT NULL)    AS kosong_tapi_ada_nama,  -- 375
    count(*) FILTER (WHERE OrderID IS NULL OR ProductName IS NULL OR Category IS NULL
                     OR Quantity IS NULL OR Price IS NULL OR OrderDate IS NULL) AS kolom_lain_kosong,  -- 0
    count(*) FILTER (WHERE Quantity <= 0)                                    AS kuantitas_tak_positif, -- 200
    count(*) FILTER (WHERE Quantity = 0)                                     AS kuantitas_nol,         -- 0
    min(Quantity) AS qty_min, max(Quantity) AS qty_max,                                                -- -3 dan 3
    count(*) FILTER (WHERE Price <= 0)                                       AS harga_nol,             -- 150
    count(*) FILTER (WHERE NOT regexp_matches(OrderID, '^ORD-\d{5}$')
                     OR (ProductID IS NOT NULL AND NOT regexp_matches(ProductID, '^PRD-\d{2}$'))) AS id_tidak_sah -- 0
FROM order_items;

-- Konsistensi antar-kolom
SELECT
    (SELECT count(DISTINCT (ProductName, ProductID)) FROM order_items WHERE ProductID IS NOT NULL) AS pasangan_nama_id, -- 15 (pemetaan 1:1)
    (SELECT max(k) FROM (SELECT count(DISTINCT Category) k FROM order_items GROUP BY ProductName)) AS kategori_per_produk, -- 1
    (SELECT max(k) FROM (SELECT count(DISTINCT OrderDate) k FROM order_items GROUP BY OrderID))   AS tanggal_per_order,   -- 1
    (SELECT round(max(greatest(mx / md - 1, 1 - mn / md)) * 100, 1) FROM (
        SELECT median(Price) md, max(Price) mx, min(Price) mn
        FROM order_items WHERE Price > 0 GROUP BY ProductName))                                  AS simpangan_harga_maks_pct; -- 5,2
```

```sql
-- Kenapa angka profil berbeda dari angka pipeline
SELECT
    (SELECT count(*) FROM order_items WHERE ProductID IS NULL)  AS pid_kosong_mentah,   -- 375
    (SELECT count(*) FROM deduped     WHERE ProductID IS NULL)  AS pid_kosong_dedup,    -- 374: selisih 1 = duplikat
    (SELECT count(*) FROM order_items WHERE Price <= 0)         AS harga_nol_mentah,    -- 150
    (SELECT count(*) FROM deduped     WHERE Price <= 0)         AS harga_nol_dedup,     -- 150: tidak ada duplikat
    (SELECT count(*) FROM deduped WHERE Price <= 0 AND Quantity <= 0
        AND ProductID IS NOT NULL)                              AS retur_sekaligus_gratis; -- 3: sudah keluar di tahap Quantity
```

### 12.4 Retur, sampel gratis, dan penggandaan oleh duplikat
```sql
-- Retur dan sampel gratis: bagaimana kaitannya dengan pembelian di order yang sama
WITH per_produk AS (
    SELECT OrderID, ProductID,
           sum(Quantity) FILTER (WHERE Quantity > 0 AND Price > 0) AS beli,
           sum(Quantity) FILTER (WHERE Quantity <= 0)              AS retur
    FROM deduped WHERE ProductID IS NOT NULL
    GROUP BY 1, 2
)
SELECT
    count(*) FILTER (WHERE beli IS NOT NULL AND retur IS NOT NULL AND beli + retur <= 0) AS dibeli_lalu_retur_penuh, -- 16
    (SELECT count(*) FROM deduped a WHERE Quantity <= 0 AND ProductID IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM deduped b WHERE b.OrderID = a.OrderID
                        AND b.ProductID = a.ProductID AND b.Quantity > 0))               AS retur_tanpa_pembelian, -- 184
    (SELECT count(*) FROM deduped a WHERE Price <= 0 AND ProductID IS NOT NULL
        AND EXISTS (SELECT 1 FROM deduped b WHERE b.OrderID = a.OrderID
                    AND b.ProductID = a.ProductID AND b.Price > 0))                      AS gratis_produk_juga_dibeli -- 20
FROM per_produk;
```

```sql
-- Seberapa besar duplikat menggandakan pasangan
CREATE OR REPLACE TABLE tanpa_dedup AS
    SELECT * FROM order_items
    WHERE ProductID IS NOT NULL AND ProductID <> '' AND Quantity > 0 AND Price > 0;

SELECT
    (SELECT count(*) FROM order_items a JOIN order_items b
        ON a.OrderID = b.OrderID WHERE a.ProductID < b.ProductID) AS pasangan_tabel_mentah,  -- 53.733
    (SELECT count(*) FROM tanpa_dedup a JOIN tanpa_dedup b
        ON a.OrderID = b.OrderID WHERE a.ProductID < b.ProductID) AS pasangan_tanpa_dedup,   -- 51.719
    (SELECT count(*) FROM keranjang a JOIN keranjang b
        ON a.OrderID = b.OrderID WHERE a.ProductID < b.ProductID) AS pasangan_keranjang;     -- 47.033

-- Sebarannya per order
WITH x AS (SELECT OrderID, count(*) p FROM tanpa_dedup a JOIN tanpa_dedup b USING (OrderID)
           WHERE a.ProductID < b.ProductID GROUP BY 1),
     y AS (SELECT OrderID, count(*) p FROM keranjang a JOIN keranjang b USING (OrderID)
           WHERE a.ProductID < b.ProductID GROUP BY 1),
     d AS (SELECT x.p - coalesce(y.p, 0) AS ekstra FROM x LEFT JOIN y USING (OrderID))
SELECT count(*) FILTER (WHERE ekstra > 0)  AS order_terkena,   -- 729
       median(ekstra) FILTER (WHERE ekstra > 0) AS median_ekstra, -- 6
       max(ekstra)                         AS ekstra_terbanyak -- 30
FROM d;
```

```sql
-- Ukuran keranjang: order besar menyumbang pasangan secara kuadratik
WITH u AS (SELECT OrderID, count(*) AS n FROM keranjang GROUP BY 1)
SELECT
    round(avg(n), 2)                                                            AS produk_per_keranjang,   -- 5,75
    median(n)                                                                   AS median,                 -- 6
    round(100.0 * count(*) FILTER (WHERE n >= 7) / count(*), 1)                 AS pct_order_7_ke_atas,    -- 33,1
    round(100.0 * sum(n*(n-1)/2) FILTER (WHERE n >= 7) / sum(n*(n-1)/2), 1)     AS pct_pasangan_7_ke_atas  -- 61,5
FROM u;
```

### 12.5 Saringan, ambang, kategori, batas lift, dan popularitas produk
```sql
-- Efek tiap syarat, diterapkan berurutan
SELECT
    count(*)                                                        AS semua,           -- 105
    count(*) FILTER (WHERE lift > 1)                                AS lift_di_atas_1,  -- 47
    count(*) FILTER (WHERE lift > 1 AND bersama >= 200)             AS plus_ambang,     -- 34
    count(*) FILTER (WHERE lift > 1 AND bersama >= 200 AND z > 1.96) AS plus_z,         -- 3
    count(*) FILTER (WHERE lift > 1 AND z > 1.96)                   AS lolos_uji_kebetulan, -- 4
    round(max(z) FILTER (WHERE lift > 1 AND z <= 1.96), 2)          AS z_tertinggi_derau    -- 1,36
FROM metrik;

-- Ambang digeser: dua susunan saringan berdampingan
SELECT a.ambang,
       count(*) FILTER (WHERE m.lift > 1 AND m.bersama >= a.ambang)                 AS lift_saja,
       count(*) FILTER (WHERE m.lift > 1 AND m.bersama >= a.ambang AND m.z > 1.96)  AS tiga_syarat
FROM (SELECT unnest([0, 100, 146, 147, 200, 800, 1200, 1231, 1232, 1300]) AS ambang) a
CROSS JOIN metrik m
GROUP BY a.ambang ORDER BY a.ambang;
```

```sql
-- Lintas kategori lawan satu kategori: rata-rata, median, dan hubungan nyata
WITH k AS (SELECT DISTINCT ProductID, Category FROM bersih),
x AS (
    SELECT m.*, (ka.Category <> kb.Category) AS lintas,
           (m.pa = 'PRD-14' AND m.pb = 'PRD-15') AS ditolak
    FROM metrik m JOIN k ka ON ka.ProductID = m.pa JOIN k kb ON kb.ProductID = m.pb
)
SELECT lintas, count(*) AS pasangan,
       round(avg(lift), 3)                              AS rata_rata,          -- 1,004 dan 1,442
       round(median(lift), 3)                           AS median,             -- 0,995 dan 0,999
       round(avg(lift) FILTER (WHERE NOT ditolak), 3)   AS rata_rata_tanpa_yang_ditolak, -- 1,004 dan 1,027
       count(*) FILTER (WHERE lift > 1)                 AS lift_di_atas_1,     -- 33 dan 14
       count(*) FILTER (WHERE lift > 1 AND z > 1.96)    AS hubungan_nyata      -- 1 dan 3
FROM x GROUP BY lintas ORDER BY lintas DESC;
```

```sql
-- Batas maksimum lift, dan ruang tumbuh tiap pasangan
SELECT n.ProductName || ' + ' || n2.ProductName AS pasangan,
       m.bersama, round(m.lift, 2) AS lift, round(m.batas_lift, 2) AS batas_lift,
       round(100 * m.lift / m.batas_lift, 1) AS persen_dari_batas,
       round(100 * greatest(m.conf_a_ke_b, m.conf_b_ke_a), 1) AS conf_terkuat,
       round(100 * least(m.conf_a_ke_b, m.conf_b_ke_a), 1)    AS conf_arah_lain,
       CAST(m.ruang_tumbuh AS BIGINT) AS ruang_tumbuh
FROM metrik m
JOIN (SELECT DISTINCT ProductID, ProductName FROM bersih) n  ON n.ProductID  = m.pa
JOIN (SELECT DISTINCT ProductID, ProductName FROM bersih) n2 ON n2.ProductID = m.pb
WHERE (m.pa, m.pb) IN (('PRD-14','PRD-15'), ('PRD-06','PRD-09'), ('PRD-01','PRD-11'), ('PRD-03','PRD-04'))
ORDER BY m.lift DESC;

-- Lift dan batasnya bergerak bersama di seluruh 105 pasangan
SELECT round(corr(lift, batas_lift), 2) AS korelasi FROM metrik;   -- 0,91
```

```sql
-- Popularitas tiap produk, dan jurang di ekor bawah
SELECT k.ProductID, n.ProductName, n.Category, count(*) AS keranjang,
       round(100.0 * count(*) / 3000, 1) AS persen
FROM keranjang k JOIN (SELECT DISTINCT ProductID, ProductName, Category FROM bersih) n USING (ProductID)
GROUP BY ALL ORDER BY keranjang DESC;
```

### 12.6 Variasi enam bulan
```sql
-- Variasi: enam bulan terakhir (order sejak 1 Oktober 2025)
-- Penyaring tanggal dipasang di tahap PALING AWAL, sebelum keranjang dibentuk
CREATE OR REPLACE TABLE keranjang_6b AS
SELECT DISTINCT OrderID, ProductID FROM (
    SELECT DISTINCT * FROM order_items WHERE OrderDate >= DATE '2025-10-01'
) WHERE ProductID IS NOT NULL AND ProductID <> '' AND Quantity > 0 AND Price > 0;

-- Ambang diturunkan sebanding: 200 x 1.218 / 3.000 = 81
SELECT pa, pb, bersama, round(100.0 * bersama / n, 1) AS persen_keranjang,
       round(lift, 2) AS lift, round(z, 1) AS z
FROM asosiasi('keranjang_6b')
WHERE lift > 1 AND bersama >= round(200 * n / 3000) AND z > 1.96
ORDER BY lift DESC;

-- Nasib pasangan yang ditolak di periode ini
SELECT bersama, round(lift, 2) AS lift FROM asosiasi('keranjang_6b')
WHERE pa = 'PRD-14' AND pb = 'PRD-15';                              -- 56 keranjang, 13,64
```

### 12.7 Lima kuartal terpisah
```sql
-- Lima kuartal dihitung terpisah, ambang sebanding tiap kuartal
CREATE OR REPLACE TABLE keranjang_q AS
SELECT DISTINCT OrderID, ProductID, date_trunc('quarter', OrderDate) AS kuartal
FROM bersih;

WITH t AS (SELECT kuartal, count(DISTINCT OrderID)::DOUBLE n FROM keranjang_q GROUP BY 1),
sp AS (SELECT kuartal, ProductID, count(*)::DOUBLE op FROM keranjang_q GROUP BY 1, 2),
p AS (SELECT a.kuartal, a.ProductID pa, b.ProductID pb, count(*)::DOUBLE bersama
      FROM keranjang_q a JOIN keranjang_q b ON a.OrderID = b.OrderID AND a.kuartal = b.kuartal
      WHERE a.ProductID < b.ProductID GROUP BY 1, 2, 3),
m AS (SELECT p.*, t.n, round(200 * t.n / 3000) AS ambang,
             p.bersama * t.n / (sa.op * sb.op) AS lift,
             (p.bersama - sa.op * sb.op / t.n)
               / sqrt(t.n * (sa.op/t.n) * (sb.op/t.n) * (1 - (sa.op/t.n) * (sb.op/t.n))) AS z
      FROM p JOIN t USING (kuartal)
      JOIN sp sa ON sa.kuartal = p.kuartal AND sa.ProductID = p.pa
      JOIN sp sb ON sb.kuartal = p.kuartal AND sb.ProductID = p.pb)
SELECT kuartal, any_value(n) AS keranjang, any_value(ambang) AS ambang,
       string_agg(pa || '+' || pb || ' (' || CAST(bersama AS INT) || ', ' || round(lift, 2) || ')', '; '
                  ORDER BY lift DESC) FILTER (WHERE lift > 1 AND bersama >= ambang AND z > 1.96) AS lolos,
       max(bersama) FILTER (WHERE pa = 'PRD-14' AND pb = 'PRD-15') AS keranjang_pasangan_ditolak,
       count(*) FILTER (WHERE lift > 1) AS lift_di_atas_1
FROM m GROUP BY kuartal ORDER BY kuartal;
```

### 12.8 Keputusan pembersihan dibalik satu per satu
```sql
-- Empat keputusan pembersihan dibalik satu per satu, plus keranjang neto.
-- Hasil yang dicari: apakah tiga bundel yang sama tetap lolos dengan ambang 200.
CREATE OR REPLACE TABLE peta_nama AS
    SELECT DISTINCT ProductName, ProductID FROM order_items WHERE ProductID IS NOT NULL;

CREATE OR REPLACE TABLE k_pulih AS                -- ProductID dipulihkan dari nama produk
SELECT DISTINCT OrderID, ProductID FROM (
    SELECT DISTINCT o.OrderID, coalesce(o.ProductID, pm.ProductID) AS ProductID,
           o.ProductName, o.Category, o.Quantity, o.Price, o.OrderDate
    FROM order_items o LEFT JOIN peta_nama pm USING (ProductName))
WHERE Quantity > 0 AND Price > 0;

CREATE OR REPLACE TABLE k_retur AS                -- retur dibiarkan
SELECT DISTINCT OrderID, ProductID FROM teridentifikasi WHERE Price > 0;

CREATE OR REPLACE TABLE k_gratis AS               -- sampel gratis dibiarkan
SELECT DISTINCT OrderID, ProductID FROM teridentifikasi WHERE Quantity > 0;

CREATE OR REPLACE TABLE k_keduanya AS             -- retur dan sampel gratis dibiarkan
SELECT DISTINCT OrderID, ProductID FROM teridentifikasi;

CREATE OR REPLACE TABLE k_neto AS                 -- produk yang dibeli lalu diretur penuh dikeluarkan
SELECT OrderID, ProductID FROM teridentifikasi
WHERE Price > 0 OR Quantity < 0
GROUP BY 1, 2
HAVING sum(CASE WHEN Quantity > 0 AND Price > 0 THEN Quantity
                WHEN Quantity < 0 THEN Quantity ELSE 0 END) > 0;

WITH semua AS (
    SELECT 'ProductID dipulihkan' AS skenario, * FROM asosiasi('k_pulih')
    UNION ALL SELECT 'Retur dibiarkan', * FROM asosiasi('k_retur')
    UNION ALL SELECT 'Sampel gratis dibiarkan', * FROM asosiasi('k_gratis')
    UNION ALL SELECT 'Retur dan sampel dibiarkan', * FROM asosiasi('k_keduanya')
    UNION ALL SELECT 'Keranjang neto', * FROM asosiasi('k_neto')
)
SELECT skenario,
       string_agg(pa || '+' || pb || ' (' || bersama || ', ' || round(lift, 2) || ')', '; '
                  ORDER BY lift DESC) FILTER (WHERE lift > 1 AND bersama >= 200 AND z > 1.96) AS lolos,
       max(bersama) FILTER (WHERE pa = 'PRD-14' AND pb = 'PRD-15') AS keranjang_pasangan_ditolak
FROM semua GROUP BY skenario ORDER BY skenario;
```

