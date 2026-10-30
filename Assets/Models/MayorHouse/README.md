# DigPals Mayor's Office

Bangunan voxel untuk rumah sekaligus kantor walikota, lengkap dengan teras, identitas kota, papan pengumuman, interior kantor, kamar pribadi dan model NPC.

## File

- `DigPals_MayorHouse.blend`: sumber Blender 5.2.3 LTS dengan collection terpisah untuk arsitektur, atap, interior, dekorasi, NPC dan preview.
- `MayorHouse_Architecture.fbx`: bangunan dan perabot tanpa panggung preview atau NPC.
- `Mayor_NPC.fbx`: karakter statis yang diekspor terpisah dengan kaki pada titik dasar.
- `Preview_Exterior.png`, `Preview_Interior.png`: render eksterior dan tampilan potongan interior.
- `build_mayor_house.py`, `validate_exports.py`, `validation.json`: skrip build dan hasil uji impor ulang.

Di Blender, depan bangunan menghadap -Y dan atas +Z. Tapak bangunan utama sekitar 18 × 15 unit; tinggi atap sekitar 12 unit. Jalur depan memperluas batas total menjadi sekitar 19,34 × 26,25 × 11,95 unit. Sesuaikan skala saat mengimpor agar cocok dengan lingkungan Roblox; ukuran akhir Studio belum diverifikasi.

Warna dibangun dari material sederhana dan detail geometri, termasuk huruf pada papan nama, sehingga tidak bergantung pada gambar tekstur beresolusi rendah. Material mungkin perlu disetel ulang setelah impor. FBX bangunan terdiri dari 290 mesh dan belum dioptimalkan untuk jumlah instance Roblox. NPC adalah model statis tanpa rig, animasi, dialog atau perilaku gameplay.

Kedua FBX berhasil diimpor ulang di Blender dan memiliki geometri. Pengujian tampilan, skala, collision, performa, serta navigasi pintu di Roblox Studio masih diperlukan. Tidak ada perubahan pada game atau publikasi live.
