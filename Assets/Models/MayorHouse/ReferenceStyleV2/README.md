# Rumah Walikota — Reference Style V2

Versi ini mengikuti ciri Merchant dan Shovelkeeper: papan dinding merah gelap, atap arang bergenteng, balok kayu gelap berlapis, fondasi bata, tiang berpengikat logam, serta papan nama gelap dengan bingkai emas. Teras formal, area kantor, ruang pribadi dan NPC tetap tersedia.

- `DigPals_MayorHouse.blend`: sumber yang bisa diedit, dengan koleksi bangunan, atap, interior, dekorasi, NPC dan preview.
- `MayorHouse_Architecture.fbx`: ekspor bangunan dan interior, digabung menjadi 37 mesh menurut material dan bagian bangunan. Preview ground tidak termasuk.
- `Mayor_NPC.fbx`: model NPC statis yang diekspor terpisah.
- `Preview_Exterior.png`, `Preview_Interior.png`: render eksterior dan interior potongan.
- `validation.json`: hasil uji impor ulang FBX di Blender.

Detail dinding, genteng, bata dan tulisan papan nama menggunakan geometri serta material warna, bukan tekstur gambar beresolusi rendah. Pembacaan detail tetap bergantung pada jarak, pencahayaan dan pengaturan tampilan game; material perlu diperiksa setelah impor ke Roblox.

Kedua FBX berhasil diimpor ulang di Blender. Ekspor bangunan memiliki 32.630 vertices dan 28.668 polygons, dengan maksimum 17.004 segitiga pada satu mesh hasil impor ulang. NPC terdiri dari 24 mesh dan belum memiliki rig, animasi atau dialog. Tampilan, skala, collision, akses pintu dan performa di Roblox Studio belum diuji; belum ada publikasi live.

Depan model di Blender menghadap -Y, dengan +Z ke atas. Ukuran tapak utama sekitar 18 × 15 unit; seluruh bangunan dan jalur sekitar 19,34 × 26,25 × 11,95 unit. Pastikan skala saat impor sesuai ukuran toko di map. Skrip build dan validasi bergantung pada skrip di folder induk `MayorHouse`; jalankan `build_reference_v2.py`, kemudian `finalize_v2.py`, lalu `validate_v2.py` untuk membangun ulang.
