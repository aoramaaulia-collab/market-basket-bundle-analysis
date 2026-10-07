-- ============================================================
-- MARKET BASKET ANALYSIS: ShopEase Indonesia
-- Analyst: Aulia Aorama
-- Date: 14 September 2026
-- Stakeholder: Mbak Dian (Head of Product/Merchandising)
-- Decision: Cross-sell bundle strategy untuk Ramadan campaign
-- Engine: DuckDB (berkas order_items.csv)
--
-- Gerbang penerimaan (semua cocok):
--   mentah      18.815
--   dedup       17.980   (buang   835 duplikat persis)
--   ProductID   17.606   (buang   374 ProductID kosong)
--   Quantity    17.406   (buang   200 retur)
--   Price       17.259   (buang   147 sampel gratis)
--   keranjang    3.000 · pasangan 105 · lift > 1: 47 · lolos tiga syarat: 3
--
-- Cara menjalankan: jalankan berkas ini dari atas ke bawah di DuckDB.
-- Setiap section bisa dijalankan ulang sendiri sesudah SECTION 0.
-- ============================================================

-- ============================================================
-- SECTION 0: MUAT DATA
-- ============================================================
-- Muat data (DuckDB). Sesuaikan path berkasnya.
CREATE OR REPLACE TABLE order_items AS
SELECT * FROM read_csv_auto('order_items.csv');

-- ============================================================
-- SECTION 1: PEMBERSIHAN + KERANJANG + ASOSIASI (kueri final)
-- Hasil: 3 baris, diurutkan menurut lift.
-- ============================================================
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

-- ============================================================
-- SECTION 2: CLEANING LOG
-- Keluaran: 18.815 | 835 | 17.980 | 374 | 17.606 | 200 | 17.406 | 147 | 17.259
-- Catatan: profil menghitung 375 ProductID kosong dan 150 harga nol.
--   375 -> 374 karena 1 baris ProductID kosong adalah duplikat.
--   150 -> 147 karena 3 baris sekaligus retur dan harga nol, sudah keluar
--   di tahap Quantity. Tidak ada baris harga nol yang duplikat.
-- ============================================================
WITH raw_data AS (
    SELECT OrderID, ProductID, ProductName, Category, Quantity, Price, OrderDate
    FROM order_items
),
deduped AS (SELECT DISTINCT * FROM raw_data),
teridentifikasi AS (SELECT * FROM deduped WHERE ProductID IS NOT NULL AND ProductID <> ''),
dibeli AS (SELECT * FROM teridentifikasi WHERE Quantity > 0),
bersih AS (SELECT * FROM dibeli WHERE Price > 0),
cleaning_counts AS (
    SELECT
        (SELECT count(*) FROM raw_data)        AS raw_rows,
        (SELECT count(*) FROM deduped)         AS rows_after_dedup,
        (SELECT count(*) FROM teridentifikasi) AS rows_after_product,
        (SELECT count(*) FROM dibeli)          AS rows_after_quantity,
        (SELECT count(*) FROM bersih)          AS clean_rows
)
SELECT
    raw_rows,
    raw_rows - rows_after_dedup              AS duplicate_rows_removed,
    rows_after_dedup,
    rows_after_dedup - rows_after_product    AS null_product_rows_removed,
    rows_after_product,
    rows_after_product - rows_after_quantity AS return_rows_removed,
    rows_after_quantity,
    rows_after_quantity - clean_rows         AS free_sample_rows_removed,
    clean_rows
FROM cleaning_counts;

-- ============================================================
-- SECTION 3: PEMERIKSAAN ARITMETIKA
-- Tabel kerja dibuat sekali supaya setiap pemeriksaan bisa dijalankan
-- sendiri (CTE hanya hidup di dalam satu statement).
-- ============================================================
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

-- ============================================================
-- SECTION 4: VARIASI, POTONGAN ENAM BULAN TERAKHIR
-- Pertanyaan Mbak Dian: kalau dibatasi pada order sejak 1 Oktober 2025,
-- apakah rekomendasinya berubah?
--
-- Hasil:
--   keranjang 1.218 (dari 3.000); ambang diturunkan sebanding menjadi 81
--   (200 x 1.218 / 3.000). Memakai 200 apa adanya berarti menaikkan syarat diam-diam.
--   Bundel lolos: tiga yang sama, urutan sama.
--     Matte Lip Cream + Lip Liner             515 keranjang (42,3%), lift 1,64 (penuh 1,68)
--     Brightening Serum + Eye Cream           552 keranjang (45,3%), lift 1,47 (penuh 1,48)
--     Daily Moisturizer + Sunscreen SPF50     577 keranjang (47,4%), lift 1,37 (penuh 1,41)
--   Pasangan yang ditolak: 56 keranjang, lift 13,64; tetap di bawah ambang 81.
--   Porsi keranjang ketiga bundel naik tipis, lift-nya turun tipis.
--   Rekomendasi TIDAK berubah. Angka periode ini tidak dipakai di berkas lain
--   kecuali disebut sebagai angka enam bulan.
-- ============================================================
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


-- Pemeriksaan tambahan: lima kuartal terpisah dan keputusan pembersihan dibalik.
-- Hasil: tiga bundel yang sama lolos di setiap kuartal dan setiap skenario.
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

-- ============================================================
-- SECTION 5: CATATAN KEPUTUSAN (ringkas; nomor dan alasan lengkap di
-- catatan-keputusan_basket_2026-09-14.md bagian 2, 8, dan 9)
-- ============================================================
/*
   Stakeholder: Mbak Dian (Head of Product/Merchandising)

   KEPUTUSAN ANALISIS DAN ALASANNYA
   K1   Empat jenis baris dibuang: duplikat persis, ProductID kosong, retur, dan sampel gratis.
     Alasan: keempatnya bukan pilihan belanja pembeli.
   K2   Keranjang dibentuk sebagai himpunan produk unik per order.
     Alasan: yang ditanyakan adalah produk apa yang muncul bersama, dan
     baris ganda mengalikan hitungan pasangan.
   K3   Seluruh pembersihan selesai sebelum self-join.
     Alasan: asal baris hilang begitu pasangan terbentuk.
   K4   Support, confidence dua arah, dan lift ditampilkan berdampingan, selalu dengan jumlah keranjang di sebelah rasionya.
     Alasan: tiap metrik buta terhadap hal yang berbeda.
   K5   Kekuatan hubungan dibandingkan terhadap batas maksimumnya.
     Alasan: batas lift ditentukan oleh produk yang lebih populer.
   K6   Uji kebetulan memakai z dengan galat baku binomial.
     Alasan: peluang kemunculan bersama terlalu besar untuk rumus Poisson.
   K7   Ambang bukti 200 keranjang.
     Alasan: tiap bundel memakan porsi anggaran yang sama besar entah
     berhasil atau tidak.
   K8   Saringan memakai tiga syarat sekaligus: lift di atas 1, minimal 200 keranjang, dan z di atas 1,96.
     Alasan: tiap syarat menutup lubang yang ditinggalkan dua lainnya.
   K9   Lintas kategori dilaporkan sebagai kolom, bukan dipakai sebagai saringan.
     Alasan: dua dari tiga bundel yang layak justru satu kategori.
   K10  Pada potongan enam bulan, ambang diturunkan sebanding menjadi 81 keranjang.
     Alasan: memakai 200 apa adanya berarti menaikkan syarat diam-diam.

   REKOMENDASI DAN ALASANNYA
   R1   Pasang tiga bundel: Matte Lip Cream + Lip Liner, Brightening Serum +
Eye Cream, dan Daily Moisturizer + Sunscreen SPF50.
     Alasan: hanya ketiganya yang lolos ketiga syarat dari 105 pasangan,
     dengan jangkauan 1.231 sampai 1.395 dari 3.000 keranjang, dan
     hasilnya sama di dua belas cara menghitung ulang.
   R2   Jalankan ketiganya sebagai uji dengan kelompok pembanding, bukan
langsung penuh: sebagian pembeli melihat bundel, sebagian tidak.
     Alasan: data hanya menunjukkan apa yang sudah dibeli bersama; tanpa
     pembanding, kenaikan penjualan tidak bisa dibedakan dari pembelian
     yang memang sudah terjadi.
   R3   Jangan kampanyekan Eye Primer + Eyeliner Pen; pasang di rekomendasi
otomatis halaman produk.
     Alasan: hubungannya nyata dan sama kuat terhadap batas maksimumnya,
     tetapi hanya menyentuh 146 dari 3.000 keranjang dengan biaya kampanye
     yang sama.
   R4   Kalau anggaran hanya cukup untuk dua uji: jalankan Brightening Serum +
Eye Cream dan Daily Moisturizer + Sunscreen SPF50, tunda Matte Lip
Cream + Lip Liner.
     Alasan: ruang tumbuh Matte Lip Cream + Lip Liner paling kecil (507
     keranjang), dan Brightening Serum + Eye Cream satu-satunya hubungan
     nyata lintas kategori.

   BATAS DAN ALASANNYA
   B1   Penjualan tambahan dari bundel tidak bisa diperkirakan.
     Alasan dan akibat: tidak ada data hasil kampanye; karena itu tidak
     ada klaim kenaikan penjualan, dan rekomendasi berbentuk uji.
   B2   Semua persentase adalah persentase keranjang, bukan persentase orang.
     Alasan dan akibat: tidak ada ID pelanggan; setiap angka ditulis
     dengan penyebut keranjang.
   B3   Margin bundel tidak dinilai.
     Alasan dan akibat: harga pokok tidak ada; besaran diskon perlu
     dihitung tim keuangan sebelum uji.
   B4   Ambang bukti 200 keranjang adalah keputusan analis, bukan sifat data.
     Alasan dan akibat: angka itu tidak berasal dari data; sudah diuji dan
     hasilnya stabil antara 200 dan 1.200.
   B5   Pembuangan retur tidak membatalkan semua pembelian yang diretur.
     Alasan dan akibat: 16 retur penuh tetap terhitung dan 184 retur tidak
     tertaut; diuji dengan keranjang neto, hasilnya sama.
   B6   375 baris ProductID kosong dibuang, padahal produknya bisa dikenali dari nama.
     Alasan dan akibat: dibuang supaya cocok dengan gerbang angka; diuji
     dengan dipulihkan, hasilnya sama.
   B7   Alasan orang membeli dan produk yang tidak jadi dibeli tidak terlihat.
     Alasan dan akibat: data hanya memuat transaksi yang selesai; alasan
     pemakaian bundel adalah tafsiran.
   B8   Hasil ini bergantung pada syarat z.
     Alasan dan akibat: tanpa syarat z, 34 pasangan lolos; syarat z
     dipertahankan di setiap potongan.

   YANG AKAN MEMBATALKAN
   Uji kelompok pembanding yang menunjukkan selisih nol antara pembeli
   yang melihat bundel dan yang tidak. Satu pertanyaan tidak bisa dijawab
   dari data ini: kalau orang sudah membeli kedua produk bersama tanpa
   diskon, bundelnya mungkin hanya membiayai pembelian yang memang sudah
   terjadi. Uji kelompok pembanding dirancang tepat untuk menjawab itu.
*/
