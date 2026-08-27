const fs = require('fs');
const crypto = require('crypto');
const { Client } = require('pg');

function envFile(path) {
  const out = {};
  for (const line of fs.readFileSync(path, 'utf8').split(/\r?\n/)) {
    const m = line.match(/^\s*([^#][A-Za-z0-9_]*)\s*=\s*(.*)\s*$/);
    if (m) out[m[1]] = m[2].trim().replace(/^['"]|['"]$/g, '');
  }
  return out;
}

const locations = [
  ['Київські пагорби над Дніпром', 'Тиха оглядова точка з широким краєвидом на Дніпро. Найкраще приходити на світанку.', 50.4547, 30.5238, 'nature'],
  ['Тиха набережна Оболоні', 'Прогулянкова ділянка біля води з лавками та простором для спокійного відпочинку.', 50.5122, 30.4983, 'nature'],
  ['Захід сонця біля Дніпра', 'Відкрита панорамна точка для вечірніх прогулянок і фотографій.', 50.4415, 30.5617, 'nature'],
  ['Лісова стежка Пущі-Водиці', 'Затінена лісова стежка для неквапливої прогулянки подалі від міського шуму.', 50.5568, 30.3334, 'nature'],
  ['Озеро в Пущі-Водиці', 'Спокійне лісове озеро з місцями для відпочинку на березі.', 50.5701, 30.3204, 'nature'],
  ['Голосіївський ліс', 'Велика зелена зона з пішохідними маршрутами та прохолодою влітку.', 50.3732, 30.4898, 'nature'],
  ['Голосіївські ставки', 'Тиха водойма серед зелені, зручна для короткої прогулянки.', 50.3696, 30.5012, 'nature'],
  ['Оглядова точка на Дніпро', 'Висока точка з відкритим видом на річку та лівобережжя.', 50.4468, 30.5441, 'nature'],
  ['Стежка Труханового острова', 'Рівна прогулянкова стежка серед дерев і широких луків.', 50.4681, 30.5579, 'nature'],
  ['Берег Десенки', 'Тихий берег із природним краєвидом і місцем для короткої зупинки.', 50.5094, 30.5746, 'nature'],
  ['Парк Муромець', 'Просторий парк для прогулянок, велосипедних поїздок і відпочинку на природі.', 50.5107, 30.5487, 'nature'],
  ['Парк Наталка', 'Доглянута набережна з алеями, газонами та видом на воду.', 50.4937, 30.5122, 'nature'],
  ['Сирецький дендропарк', 'Зелений парк із різноманітними деревами та затишними алеями.', 50.4708, 30.4245, 'nature'],
  ['Парк Кинь-Грусть', 'Спокійна лісопаркова зона для повільної прогулянки.', 50.5158, 30.4384, 'nature'],
  ['Совські ставки', 'Невелика природна зона з водою та пішохідними стежками.', 50.4081, 30.5073, 'nature'],
  ['Лиса гора', 'Природний пагорб із відкритим горизонтом і відчуттям заміської тиші.', 50.3987, 30.5524, 'nature'],
  ['Феофанія', 'Парк із тінистими алеями, джерелами та місцями для спокійного відпочинку.', 50.3507, 30.4771, 'nature'],
  ['Китаївські озера', 'Лісова прогулянкова зона з невеликими озерами та пагорбами.', 50.3469, 30.5348, 'nature'],
  ['Пирогівські пагорби', 'Відкрита зелена місцевість із м’якими пагорбами та далеким краєвидом.', 50.3895, 30.5087, 'nature'],
  ['ВДНГ — лісова зона', 'Тиха зелена частина комплексу для прогулянок між міськими активностями.', 50.3804, 30.4786, 'nature'],
  ['Межигірські краєвиди', 'Панорамна природна зона на схилах над водою.', 50.6172, 30.4421, 'nature'],
  ['Київське море — берег', 'Відкритий берег із широким видом на водосховище.', 50.6879, 30.6045, 'nature'],
  ['Вишгородська оглядова точка', 'Спокійне місце над схилом із видом на Дніпро та околиці.', 50.5843, 30.4928, 'nature'],
  ['Ліс біля Вишгорода', 'Лісова зона для короткого маршруту неподалік міста.', 50.6038, 30.4752, 'nature'],
  ['Ірпінська набережна', 'Прогулянкова зона біля річки з деревами та відкритими просторами.', 50.5216, 30.2458, 'nature'],
  ['Центральний парк Ірпеня', 'Міський парк для легкої прогулянки, відпочинку та активностей.', 50.5182, 30.2511, 'nature'],
  ['Бучанський міський парк', 'Великий доглянутий парк із водоймою та зеленими алеями.', 50.5535, 30.2137, 'nature'],
  ['Лісова зона Бучі', 'Тиха соснова ділянка для прогулянки на свіжому повітрі.', 50.5467, 30.2042, 'nature'],
  ['Озеро біля Горенки', 'Невелике озеро з природним берегом і місцями для споглядання.', 50.5618, 30.3867, 'nature'],
  ['Стоянка — лісова зона', 'Лісова зупинка біля села Стоянка для короткої паузи в дорозі.', 50.4557, 30.1524, 'nature'],
  ['Горенка — сосновий ліс', 'Сосновий ліс із рівними стежками та чистим повітрям.', 50.5551, 30.3654, 'nature'],
  ['Білогородські пагорби', 'Відкриті пагорби з видом на поля та західне передмістя Києва.', 50.3838, 30.2189, 'nature'],
  ['Ліс біля Боярки', 'Затінений лісовий маршрут для тихої прогулянки.', 50.3195, 30.2922, 'nature'],
  ['Озеро в Боярці', 'Спокійна водойма для короткого відпочинку неподалік міста.', 50.3161, 30.2957, 'nature'],
  ['Віта-Поштова — зелені пагорби', 'Зелена околиця з плавними схилами та сільським краєвидом.', 50.2846, 30.4439, 'nature'],
  ['Ходосівські пагорби', 'Відкрита природна зона для панорамної прогулянки.', 50.2952, 30.5075, 'nature'],
  ['Блакитне озеро Підгірці', 'Водойма з відкритим берегом і простором для спокійного відпочинку.', 50.2417, 30.6282, 'nature'],
  ['Лісова зона Нових Безрадичів', 'Тиха лісова місцевість для неквапливої прогулянки.', 50.2314, 30.6905, 'nature'],
  ['Українка — берег Дніпра', 'Прогулянковий берег із видом на воду та широкі заплавні простори.', 50.1438, 30.7464, 'nature'],
  ['Трипільські пагорби', 'Відкриті пагорби над Дніпром із сильним відчуттям простору.', 50.1184, 30.7881, 'nature'],
  ['Дівички — берег Дніпра', 'Тихий природний берег для короткої зупинки та споглядання.', 50.2023, 31.0626, 'nature'],
  ['Ржищівські краєвиди', 'Панорамні схили над Дніпром у тихій заміській місцевості.', 49.9685, 31.0478, 'nature'],
  ['Затоплена церква біля Ржищева', 'Оглядова природна зона біля води; без заходу на приватні території.', 49.9844, 31.0489, 'nature'],
  ['Панорамна точка на Канівському напрямку', 'Високий берег із далеким видом на річкову долину.', 49.9175, 31.1264, 'nature'],
  ['Броварський ліс', 'Великий лісовий масив для спокійної прогулянки на схід від Києва.', 50.5354, 30.8631, 'nature'],
  ['Пухівка — берег Десни', 'Природний берег Десни з відкритим горизонтом і тихими стежками.', 50.6318, 30.7134, 'nature'],
  ['Зазим’я — берег Десни', 'Зелена берегова зона для короткої прогулянки та відпочинку.', 50.6018, 30.6717, 'nature'],
  ['Погреби — тиха природна зона', 'Спокійна зелена околиця неподалік Києва, зручна для повільної прогулянки.', 50.5167, 30.6351, 'nature'],
  ['Хотянівка — берег води', 'Тихий відкритий берег у північному передмісті Києва.', 50.6311, 30.5482, 'nature'],
  ['Лютіж — Київське море', 'Відкрита берегова точка з простором для прогулянки та краєвидом на воду.', 50.6972, 30.4338, 'nature'],
];

async function main() {
  const audit = envFile('.env.audit');
  const app = envFile('.env');
  const base = (audit.SUPABASE_URL || app.SUPABASE_URL).replace(/\/$/, '');
  const secret = audit.SUPABASE_SECRET_KEY;
  const adminHeaders = { apikey: secret, Authorization: `Bearer ${secret}`, 'Content-Type': 'application/json' };
  const pooler = new URL(fs.readFileSync('supabase/.temp/pooler-url', 'utf8').trim());
  pooler.password = audit.SUPABASE_DB_PASSWORD;
  const db = new Client({ connectionString: pooler.toString(), ssl: { rejectUnauthorized: false } });
  await db.connect();

  const usersResponse = await fetch(`${base}/auth/v1/admin/users?per_page=1000&page=1`, { headers: adminHeaders });
  const usersBody = await usersResponse.json();
  const oldUsers = usersBody.users || [];
  let seedUser = oldUsers.find((user) => user.user_metadata?.purpose === 'starter_seed_owner');
  if (!seedUser) {
    const created = await fetch(`${base}/auth/v1/admin/users`, {
      method: 'POST', headers: adminHeaders,
      body: JSON.stringify({
        email: `travel-seed-${crypto.randomUUID()}@seed.invalid`,
        password: `Seed-${crypto.randomBytes(30).toString('base64url')}!9a`,
        email_confirm: true,
        user_metadata: { username: 'travel_seed', display_name: 'Travel Seed', purpose: 'starter_seed_owner' },
      }),
    });
    const body = await created.json();
    if (!created.ok || !body.id) throw new Error(`seed auth create failed HTTP ${created.status}`);
    seedUser = body;
  }

  const preserveCode = '660A140317';
  await db.query('begin');
  try {
    await db.query('update public.invites set created_by=null where code=$1', [preserveCode]);
    await db.query('delete from public.invite_redemptions');
    await db.query('delete from public.invites where code<>$1', [preserveCode]);
    await db.query('delete from public.comments');
    await db.query('delete from public.reviews');
    await db.query('delete from public.check_ins');
    await db.query('delete from public.location_photos');
    await db.query('delete from public.location_tags');
    await db.query('delete from public.location_categories');
    await db.query('delete from public.locations');
    await db.query('delete from public.notifications');
    await db.query('delete from public.messages');
    await db.query('delete from public.friendships');
    await db.query('delete from public.follows');
    await db.query('delete from public.user_achievements');
    await db.query('delete from public.user_settings');
    await db.query('delete from public.routes');
    await db.query('delete from public.profiles where id<>$1', [seedUser.id]);
    await db.query(`update public.profiles set user_id=id,name='Travel Seed',username='travel_seed',display_name='Travel Seed',xp=0,level='Новачок',invites_left=0,is_developer=false,distance_traveled_km=0,invite_redeemed=false,invited_by=null,invite_balance=0,highest_level_rewarded=1 where id=$1`, [seedUser.id]);
    const seedProfile = await db.query('select id from public.profiles where id=$1', [seedUser.id]);
    if (seedProfile.rowCount !== 1) throw new Error('seed profile trigger did not create profile');
    const values = [];
    const params = [];
    locations.forEach(([title, description, lat, lng, category], i) => {
      const id = crypto.randomUUID();
      const n = params.length;
      values.push(`($${n+1},$${n+2},$${n+3},$${n+4},public.st_setsrid(public.st_makepoint($${n+5},$${n+6}),4326)::public.geography,now()-interval '${i} minutes',null,$${n+7},true,$${n+2},$${n+3},public.st_setsrid(public.st_makepoint($${n+5},$${n+6}),4326)::public.geography,'approved'::public.location_status,'public'::public.location_visibility,'approved','public','easy',false,'unknown',0,0,0,now(),null)`);
      params.push(id, seedUser.id, title, description, lng, lat, category);
    });
    await db.query(`insert into public.locations (id,user_id,title,description,coordinates,created_at,image_url,category,is_public,owner_id,name,position,status,visibility,moderation,secrecy,road_difficulty,has_parking,safety,minimum_xp,rating,ratings_count,updated_at,request_id) values ${values.join(',')}`, params);
    await db.query('commit');
  } catch (error) {
    await db.query('rollback');
    throw error;
  }

  const objects = (await db.query(`select name from storage.objects where bucket_id='location_images'`)).rows;
  await db.end();
  for (const object of objects) {
    await fetch(`${base}/storage/v1/object/location_images/${object.name.split('/').map(encodeURIComponent).join('/')}`, { method: 'DELETE', headers: adminHeaders });
  }
  let deletedUsers = 0;
  for (const user of oldUsers) {
    if (user.id === seedUser.id) continue;
    const response = await fetch(`${base}/auth/v1/admin/users/${user.id}`, { method: 'DELETE', headers: adminHeaders });
    if (response.ok || response.status === 404) deletedUsers++;
  }
  console.log(JSON.stringify({ seed_owner_id: seedUser.id, deleted_auth_users: deletedUsers, deleted_location_images: objects.length, starter_locations: locations.length, owner_invite: preserveCode }, null, 2));
}

main().catch((error) => { console.error(`CLEAN_SEED_FATAL=${error.message}`); process.exitCode = 1; });
