import '../domain/location.dart';

/// Administrative divisions of Uzbekistan (14 top-level units).
/// Namangan is detailed down to localities for the launch region; other
/// regions carry their main districts/cities and will be completed from the
/// backend's location service.
abstract final class UzbekistanLocations {
  static const defaultRegionId = 'namangan';
  static const defaultDistrictId = 'chust';

  static const tree = LocationTree([
    Region(
      id: 'namangan',
      name: 'Namangan viloyati',
      center: GeoPoint(40.9983, 71.6726),
      districts: [
        District(
          id: 'namangan_city',
          name: 'Namangan shahri',
          center: GeoPoint(40.9983, 71.6726),
          localities: [
            Locality(id: 'nc_davlatobod', name: 'Davlatobod'),
            Locality(id: 'nc_yangi_namangan', name: 'Yangi Namangan'),
            Locality(id: 'nc_markaz', name: 'Markaz'),
          ],
        ),
        District(
          id: 'chust',
          name: 'Chust tumani',
          center: GeoPoint(41.0034, 71.2372),
          localities: [
            Locality(id: 'chust_karkidon', name: 'Karkidon'),
            Locality(id: 'chust_markaz', name: 'Markaz'),
            Locality(id: 'chust_yangi_hayot', name: 'Yangi hayot'),
            Locality(id: 'chust_olmos', name: 'Olmos'),
            Locality(id: 'chust_gova', name: 'G‘ova'),
            Locality(id: 'chust_varzik', name: 'Varzik'),
            Locality(id: 'chust_sarvak', name: 'Sarvak'),
          ],
        ),
        District(
          id: 'pop',
          name: 'Pop tumani',
          center: GeoPoint(40.8736, 71.1089),
          localities: [
            Locality(id: 'pop_markaz', name: 'Markaz'),
            Locality(id: 'pop_chodak', name: 'Chodak'),
            Locality(id: 'pop_pungon', name: 'Pungon'),
          ],
        ),
        District(id: 'chortoq', name: 'Chortoq tumani', center: GeoPoint(41.0692, 71.8237)),
        District(id: 'kosonsoy', name: 'Kosonsoy tumani', center: GeoPoint(41.2567, 71.5467)),
        District(id: 'mingbuloq', name: 'Mingbuloq tumani', center: GeoPoint(40.7639, 71.3956)),
        District(id: 'namangan_d', name: 'Namangan tumani', center: GeoPoint(40.9642, 71.6080)),
        District(id: 'norin', name: 'Norin tumani', center: GeoPoint(40.9261, 72.0564)),
        District(id: 'toraqorgon', name: 'To‘raqo‘rg‘on tumani', center: GeoPoint(41.0033, 71.5097)),
        District(id: 'uchqorgon', name: 'Uchqo‘rg‘on tumani', center: GeoPoint(41.1136, 72.0797)),
        District(id: 'uychi', name: 'Uychi tumani', center: GeoPoint(41.0806, 71.9236)),
        District(id: 'yangiqorgon', name: 'Yangiqo‘rg‘on tumani', center: GeoPoint(41.1947, 71.7231)),
      ],
    ),
    Region(
      id: 'tashkent_city',
      name: 'Toshkent shahri',
      center: GeoPoint(41.2995, 69.2401),
      districts: [
        District(id: 'yunusobod', name: 'Yunusobod tumani', center: GeoPoint(41.3650, 69.2870)),
        District(id: 'chilonzor', name: 'Chilonzor tumani', center: GeoPoint(41.2756, 69.2034)),
        District(id: 'mirzo_ulugbek', name: 'Mirzo Ulug‘bek tumani', center: GeoPoint(41.3275, 69.3350)),
        District(id: 'yakkasaroy', name: 'Yakkasaroy tumani', center: GeoPoint(41.2870, 69.2500)),
        District(id: 'shayxontohur', name: 'Shayxontohur tumani', center: GeoPoint(41.3230, 69.2280)),
        District(id: 'olmazor', name: 'Olmazor tumani', center: GeoPoint(41.3530, 69.2150)),
        District(id: 'mirobod', name: 'Mirobod tumani', center: GeoPoint(41.2900, 69.2800)),
        District(id: 'sergeli', name: 'Sergeli tumani', center: GeoPoint(41.2250, 69.2200)),
        District(id: 'uchtepa', name: 'Uchtepa tumani', center: GeoPoint(41.2900, 69.1700)),
        District(id: 'yashnobod', name: 'Yashnobod tumani', center: GeoPoint(41.2900, 69.3400)),
        District(id: 'bektemir', name: 'Bektemir tumani', center: GeoPoint(41.2090, 69.3340)),
        District(id: 'yangihayot', name: 'Yangihayot tumani', center: GeoPoint(41.2000, 69.2000)),
      ],
    ),
    Region(
      id: 'tashkent',
      name: 'Toshkent viloyati',
      center: GeoPoint(41.0, 69.6),
      districts: [
        District(id: 'nurafshon', name: 'Nurafshon shahri', center: GeoPoint(41.0400, 69.3580)),
        District(id: 'chirchiq', name: 'Chirchiq shahri', center: GeoPoint(41.4689, 69.5822)),
        District(id: 'angren', name: 'Angren shahri', center: GeoPoint(41.0167, 70.1436)),
        District(id: 'olmaliq', name: 'Olmaliq shahri', center: GeoPoint(40.8447, 69.5983)),
        District(id: 'zangiota', name: 'Zangiota tumani', center: GeoPoint(41.1900, 69.1400)),
        District(id: 'qibray', name: 'Qibray tumani', center: GeoPoint(41.3900, 69.4650)),
      ],
    ),
    Region(
      id: 'andijan',
      name: 'Andijon viloyati',
      center: GeoPoint(40.7821, 72.3442),
      districts: [
        District(id: 'andijan_city', name: 'Andijon shahri', center: GeoPoint(40.7821, 72.3442)),
        District(id: 'asaka', name: 'Asaka tumani', center: GeoPoint(40.6415, 72.2387)),
        District(id: 'xonobod', name: 'Xonobod shahri', center: GeoPoint(40.8036, 73.0020)),
        District(id: 'shahrixon', name: 'Shahrixon tumani', center: GeoPoint(40.7133, 72.0572)),
        District(id: 'baliqchi', name: 'Baliqchi tumani', center: GeoPoint(40.8667, 71.9000)),
      ],
    ),
    Region(
      id: 'fergana',
      name: 'Farg‘ona viloyati',
      center: GeoPoint(40.3842, 71.7843),
      districts: [
        District(id: 'fergana_city', name: 'Farg‘ona shahri', center: GeoPoint(40.3842, 71.7843)),
        District(id: 'margilan', name: 'Marg‘ilon shahri', center: GeoPoint(40.4711, 71.7247)),
        District(id: 'kokand', name: 'Qo‘qon shahri', center: GeoPoint(40.5286, 70.9425)),
        District(id: 'quvasoy', name: 'Quvasoy shahri', center: GeoPoint(40.2972, 71.9800)),
        District(id: 'rishton', name: 'Rishton tumani', center: GeoPoint(40.3567, 71.2847)),
      ],
    ),
    Region(
      id: 'samarkand',
      name: 'Samarqand viloyati',
      center: GeoPoint(39.6542, 66.9597),
      districts: [
        District(id: 'samarkand_city', name: 'Samarqand shahri', center: GeoPoint(39.6542, 66.9597)),
        District(id: 'urgut', name: 'Urgut tumani', center: GeoPoint(39.4022, 67.2431)),
        District(id: 'kattaqorgon', name: 'Kattaqo‘rg‘on shahri', center: GeoPoint(39.8989, 66.2561)),
        District(id: 'pastdargom', name: 'Pastdarg‘om tumani', center: GeoPoint(39.7270, 66.6600)),
      ],
    ),
    Region(
      id: 'bukhara',
      name: 'Buxoro viloyati',
      center: GeoPoint(39.7747, 64.4286),
      districts: [
        District(id: 'bukhara_city', name: 'Buxoro shahri', center: GeoPoint(39.7747, 64.4286)),
        District(id: 'kogon', name: 'Kogon shahri', center: GeoPoint(39.7222, 64.5519)),
        District(id: 'gijduvon', name: 'G‘ijduvon tumani', center: GeoPoint(40.1000, 64.6833)),
      ],
    ),
    Region(
      id: 'khorezm',
      name: 'Xorazm viloyati',
      center: GeoPoint(41.5500, 60.6333),
      districts: [
        District(id: 'urgench', name: 'Urganch shahri', center: GeoPoint(41.5500, 60.6333)),
        District(id: 'khiva', name: 'Xiva shahri', center: GeoPoint(41.3783, 60.3639)),
        District(id: 'xonqa', name: 'Xonqa tumani', center: GeoPoint(41.4744, 60.7800)),
      ],
    ),
    Region(
      id: 'karakalpakstan',
      name: 'Qoraqalpog‘iston Respublikasi',
      center: GeoPoint(42.4611, 59.6166),
      districts: [
        District(id: 'nukus', name: 'Nukus shahri', center: GeoPoint(42.4611, 59.6166)),
        District(id: 'xojayli', name: 'Xo‘jayli tumani', center: GeoPoint(42.4047, 59.4517)),
        District(id: 'tortkol', name: 'To‘rtko‘l tumani', center: GeoPoint(41.5500, 61.0000)),
      ],
    ),
    Region(
      id: 'kashkadarya',
      name: 'Qashqadaryo viloyati',
      center: GeoPoint(38.8606, 65.7847),
      districts: [
        District(id: 'karshi', name: 'Qarshi shahri', center: GeoPoint(38.8606, 65.7847)),
        District(id: 'shahrisabz', name: 'Shahrisabz shahri', center: GeoPoint(39.0578, 66.8342)),
        District(id: 'guzor', name: 'G‘uzor tumani', center: GeoPoint(38.6208, 66.2481)),
      ],
    ),
    Region(
      id: 'surkhandarya',
      name: 'Surxondaryo viloyati',
      center: GeoPoint(37.2242, 67.2783),
      districts: [
        District(id: 'termez', name: 'Termiz shahri', center: GeoPoint(37.2242, 67.2783)),
        District(id: 'denov', name: 'Denov tumani', center: GeoPoint(38.2667, 67.9000)),
        District(id: 'sherobod', name: 'Sherobod tumani', center: GeoPoint(37.6667, 67.0000)),
      ],
    ),
    Region(
      id: 'jizzakh',
      name: 'Jizzax viloyati',
      center: GeoPoint(40.1158, 67.8422),
      districts: [
        District(id: 'jizzakh_city', name: 'Jizzax shahri', center: GeoPoint(40.1158, 67.8422)),
        District(id: 'gallaorol', name: 'G‘allaorol tumani', center: GeoPoint(40.0214, 67.5956)),
        District(id: 'zomin', name: 'Zomin tumani', center: GeoPoint(39.9600, 68.3950)),
      ],
    ),
    Region(
      id: 'sirdarya',
      name: 'Sirdaryo viloyati',
      center: GeoPoint(40.4897, 68.7842),
      districts: [
        District(id: 'guliston', name: 'Guliston shahri', center: GeoPoint(40.4897, 68.7842)),
        District(id: 'yangiyer', name: 'Yangiyer shahri', center: GeoPoint(40.2750, 68.8225)),
        District(id: 'shirin', name: 'Shirin shahri', center: GeoPoint(40.2269, 69.1017)),
      ],
    ),
    Region(
      id: 'navoiy',
      name: 'Navoiy viloyati',
      center: GeoPoint(40.0844, 65.3792),
      districts: [
        District(id: 'navoiy_city', name: 'Navoiy shahri', center: GeoPoint(40.0844, 65.3792)),
        District(id: 'zarafshon', name: 'Zarafshon shahri', center: GeoPoint(41.5747, 64.2011)),
        District(id: 'karmana', name: 'Karmana tumani', center: GeoPoint(40.1367, 65.3561)),
      ],
    ),
  ]);
}
