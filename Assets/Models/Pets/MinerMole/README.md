# DigPals Miner Mole

Pet mole berwarna tanah dengan cakar besar, topi dan lampu tambang, serta kantong bijih.

`DigPals_MinerMole.blend` berisi model, rig, material, dan tiga action. Gunakan `DigPals_MinerMole_Rig.fbx` untuk model di Roblox Studio, lalu impor masing-masing file di `Animations` untuk rig tersebut. Idle dan walk dimaksudkan untuk loop; digging adalah animasi sekali putar. Semuanya dibuat pada 24 FPS.

Model berisi satu skinned mesh, 11 bones, 10.010 vertices, dan 10.476 polygons. Ukuran Blender sekitar 0,632 × 1,116 × 0,680 meter, atau kira-kira 2,26 × 3,99 × 2,43 studs dengan konversi 3,571 studs per meter. Arah depan Blender adalah -Y; ekspor FBX memakai Forward -Z dan Up Y. Pedestal dan lampu preview tidak ikut diekspor.

Semua FBX berhasil diimpor ulang di Blender dengan mesh, armature, material, bones dan rentang animasi yang terdeteksi; detailnya ada di `validation.json`. Pemeriksaan visual dan animasi di Roblox Studio masih diperlukan. Tampilan lampu dan material dapat berbeda di Roblox. Tidak ada aset yang dipublikasikan.

`build_mole.py` dan `validate_mole.py` menggunakan skrip pendamping di folder `CometMinerDog`; pertahankan kedua folder jika ingin menjalankan ulang skrip tersebut.
