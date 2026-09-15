<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# Güvenilir Agent Akışı — Geliştirme Planı

**Tarih:** 2026-09-14
**Durum (2026-09-15):** Faz 1 tamam. Faz 2'nin kapanış kararı, `.active` doğrulaması, idempotency ve resume maddeleri tamam; **taban kontrolü (A1) açık** — dar sözleşmesi ve yanlış pozitif fixture'ları belirlenmeden genel kural motoruna dönüşmemesi için ayrı bir dilim olarak bırakıldı. Faz 3'ün red-proof izolasyonu ve verifier rol sınırı tamam; worktree yaşam döngüsünün kalan tavanları `docs/specs/2026-09-07-red-proof.md` amendment'ında yazılı. Faz 4–6 kapsam dışı.
**Kabul edilmiş spec'ler:** `docs/specs/2026-09-15-verification-contract.md` (Faz 1), `docs/specs/2026-09-15-evidence-gated-closing.md` + amendment (Faz 2, kapanış), `docs/specs/2026-09-15-marker-and-resume.md` (Faz 2, marker/resume), `docs/specs/2026-09-07-red-proof.md` + amendment (Faz 3).
**Doğrulama raporu:** `docs/reports/2026-09-15-reliability-verification.md`.
**Amaç:** v5'in sade omurgasını koruyarak eksik doğrulamayla kapanışı önlemek; plan eleştirmeni ve tester rollerini gerçek iş sonuçları üzerinden değerlendirmek; paralel uygulamayı ancak izolasyon hazır olduğunda açmak.
**Temel karar:** Önce güvenilir sonuç ve kapanış sözleşmesi, sonra yeni roller, en son paralellik. v4'e toplu dönüş yok.
**Kapsam:** Plugin'in geliştirilmesi. Bu repoda `triage` çalıştırılmaz, `.se/` oluşturulmaz. Bu belge plan üretir; uygulama veya commit yetkisi vermez.
**Biçim:** Yol haritası, tek slice planı değil — `scripts/plan-validate.sh` bunu denetlemez; o linter executor'a verilen `.se/plans/<id>.md` içindir. Fazlar uygulanırken slice planları ayrıca yazılır ve linter'dan geçer.

## Başlangıç durumu ve kanıt sınırı

- Planlama kaldırılmamış: `skills/triage/references/flow-light.md:28-40` planı ana konuşmada yazdırıyor, lint ve kullanıcı kabulü istiyor.
- Gereksinim görüşmesi `skills/intent/SKILL.md`, bağlayıcı spec `skills/spec/SKILL.md` içinde mevcut.
- Executor uygular; verifier ayrı bağlamda inceler. `flow-light.md:78`, review tooling hatasında devam etmeye izin veriyor.
- `scripts/verify-phase.sh:88-90` kriterleri kaydediyor; kriterlerin gerçekleşmesini kendisi sınamıyor. `hooks/auto-qa:99-100` runner bulunmasa da bu kaydı oluşturabiliyor.
- `scripts/state-update.sh:119-130` gerekli alanların varlığını denetliyor; kapanışı doğrulama kaydına bağlamıyor.
- `.active` süreç işareti; kullanıcı onayının doğrulanmış kaydı değil. `.se/` yazımları gate dışında: `hooks/pre-guard:68-73`.
- Verifier `Bash` ve `memory: project` kullanıyor. Kaynağı düzeltmeme sorumluluğu, teknik olarak hiçbir dosyaya yazamama anlamına gelmiyor.
- `scripts/red-proof.sh:148-180` mevcut çalışma ağacında kaynakları geri alıyor. Sonradan elde edilen kırmızı sonuç, testin tarihsel olarak önce yazıldığını kanıtlamaz.
- README ve DEVELOPMENT içindeki plan-mode anlatımı güncel flow ile çelişiyor. DESIGN'ın tarihsel bölümleri ise bilinçli olarak eski davranışı anlatıyor; tamamı mekanik olarak değiştirilmemeli.
- Yeşil bir suite'in nasıl yeşile geldiğini denetleyen hiçbir kontrol yok. `hooks/auto-qa` çıkış kodunu okur; testin susturulmasıyla düzeltilmesini ayırt etmez.
- Mevcut davranışsal eval, eski/yeni agent mimarilerinin gerçek repo görevlerindeki kalite karşılaştırması değil. Bu planın rol önerileri ölçülmüş üstünlük iddiası taşımaz.

Satır numaraları araştırma anına aittir; uygulama öncesi ilgili bölüm yeniden okunur.

## Korunacak ilkeler

- Native Claude Code plugin: skills, subagents, hooks, bash/jq/git. Yeni servis, MCP sunucusu veya özel orchestration runtime yok.
- `model: inherit`; maliyet/derinlik için `effort`. Aynı model kullanımı bağımsız review kalitesinin garantisi sayılmaz.
- Gereksinim diyaloğu ve son kullanıcı kararları ana konuşmada kalır.
- Executor kendi geliştirme/regresyon testlerini yazmaya devam eder. Tester bu sorumluluğu devralmaz.
- Script mekanik olguyu kaydeder; reviewer semantik değerlendirme yapar; kullanıcı ürün/risk kararını verir.
- `state-init.sh` state'i yaratır, `state-update.sh` değiştirir. Yeni bir state yazarı eklenmez.
- Bash 3.2 uyumu, AGPL başlıkları, extensionless hook yapısı ve sıfır kullanıcı konfigürasyonu korunur.
- Hook'lar unutulan süreç adımlarına karşıdır; modelin yazabildiği yerel dosyalar kriptografik insan-onayı veya güvenlik sandbox'ı gibi sunulmaz.

## Hedef akış

```text
Kullanıcı ↔ Ana agent: intent → spec → plan → kararlar
                  ├─ Explore: ihtiyaç kadar araştırma
                  ├─ Plan eleştirisi: riskli/belirsiz işlerde, deney sonrası
                  └─ Executor: kod + geliştirme testleri
                           ↓
                    Mekanik doğrulama
                           ↓
                    Verifier: kriterler + review
                    Tester: gerekiyorsa bağımsız davranış senaryoları
                           ↓
                    Kanıta bağlı kapanış
```

Başlangıç teslimatı iki agent ile çalışır. Plan eleştirmeni ve tester kalıcı agent tanımı ancak Faz 4 ölçümüyle hak edilir. Kullanıcıya agent modu seçtirilmez.

## Ortak sonuç sözleşmesi

Faz 1'de aşağıdaki anlamlar spec'e bağlanır; bütün tüketiciler birlikte geçirilir.

| Boyut | Değerler | Anlam |
|---|---|---|
| Test | `passed`, `failed`, `not_run` | Çalıştırılmış komutun sonucu; runner yokluğu `not_run` ve neden taşır. |
| Kriter | `met`, `unmet`, `unverified` | Her kriterin kanıtı veya neden doğrulanamadığı ayrı tutulur. |
| Review | `complete`, `incomplete` | Bulgusuz review ile hiç/yarım yapılmış review farklıdır. |
| Karar | `pass`, `partial`, `fail`, `incomplete` | Akışın kapanış kararı; katmanlardan türetilir. |

Asgari kayıt: kayıt sürümü, slice id, plan blob kimliği, kaynak inceleme başlangıç/bitiş commit'leri, yürütülen komut/çıkış kodu, gerekçe. Review aynı plan ve kaynak revizyonuna referans verir; kriter kanıtlarını ve kapsam dışında kalanları taşır.

Kayıtları taşıyan artifact-only kapanış commit'i kaynak revizyonunu değiştirmiş sayılmaz. Plan veya incelenen kaynak değişirse kanıt eskir. Kaynak aralığı tanımı dokümante edilmeden yalnızca `HEAD eşit mi?` kontrolü yapılmaz.

Kapanış politikası:

- Başarısız gerekli kontrol veya blocker → kapanış yok.
- Eksik/bozuk/eski review ya da doğrulanmamış gerekli kriter → `incomplete`, kapanış yok.
- Test runner yokluğu → test geçti sayılmaz. Spec/planın gerektirdiği davranış için uygun gerçek komut veya manuel kanıt varsa reviewer bunu açıkça değerlendirir.
- `partial` → otomatik `done` yok. Bulgu düzeltilir veya kullanıcı belirli riski açıkça kabul eder; kabul edilen bulgu ve gerekçe artifact'ta korunur.
- İnsan risk kabulü, test geçti veya kriter karşılandı bilgisini geriye dönük değiştirmez; bilinen eksikle kapanış ayrı gösterilir.
- Tooling kesintisi → biten subagent mümkünse devam ettirilir. Sonuç gelmeden başarılı review varsayılmaz.

## Faz 1 — Doğrulama kayıtlarını dürüst ve revizyona bağlı hale getir

**Öncelik:** P0. **Bağımlılık:** Yok.

**Hedef dosyalar:** `scripts/verify-phase.sh`, `scripts/test-digest.sh`, `hooks/auto-qa`, `agents/verifier.md`, `skills/triage/references/flow-light.md`, `docs/STATE.md`, `examples/state/`; bunların eval tüketicileri ve `skills/se-status/SKILL.md`.

### İşler

- [x] Ortak sözleşmeyi ve v5 kayıtlardan geçişi `docs/specs/` altında kısa bir değişiklik spec'iyle kabul ettir. Tarihsel kayıtlar silinmez; yeni kapanış için yeterli kanıt taşımayan eski kayıtlar yeniden doğrulama ister.
- [x] Test komutunun gerçek sonucunu kayıt yazıcısına aktar. Yazıcı, yalnızca plan dosyası var diye `tests passed` üretmesin; serbestçe verilen başarı etiketi yerine yürütme kanıtını kullansın.
- [x] `test-digest`, flow ve Stop hook'un aynı kaynağı tekrar doğrulama davranışını haritala. İlk doğruluk geçişinde mevcut güvenceyi kaldırma; yeniden kullanım ancak aynı kaynak/plan revizyonuna bağlı sonuçla mümkün olsun.
- [x] Tier-1 kriter envanteri ile Tier-2 kriter değerlendirmesini ayır. Genel `status: pass` ifadesinin hangi boyuta ait olduğunu belirsiz bırakma.
- [x] Verifier kayıtlarını eksik inceleme, çalıştırılamayan kontroller ve incelenmeyen kapsamı ifade edecek şekilde geçir. JSON dosyası ile son mesaj çelişirse dosyanın doğrulanmış sözleşmesi karar kaynağı olsun.
- [x] Tier-2 kaydına bir yazıcı ver. Şekli bugün `agents/verifier.md` içindeki bir jq bloğu; dosyayı hiçbir şey doğrulamıyor, dolayısıyla sözleşmeye uymayan kayıt sessizce kabul ediliyor.
- [x] Bütün tüketicileri tek geçişte güncelle; eski alanları okuyan gizli ikinci karar yolu bırakma.

### Kabul ve kanıt

- [x] Runner olmayan fixture `not_run` kaydeder; hiçbir çıktı testlerin geçtiğini söylemez.
- [x] Gerçek komutun sıfır/sıfır-dışı çıkışı doğru kaydedilir; timeout başarı sayılmaz.
- [x] Plan bulunmaması, bozuk kayıt, eksik kriter kanıtı başarıya dönüşmez.
- [x] Başka slice/revizyona ait sonuç kabul edilmez; artifact-only commit gereksiz geçersizleştirme yaratmaz.
- [x] Mevcut `verify-phase`, `test-digest`, `auto-qa` eval'leri yeni anlamlarla çalışır. Yeni regresyonlar bu davranışları fixture repo üzerinde sınar, prompt kelimelerini değil.

**Teslimat:** Doğru olguları bildiren Tier-1/Tier-2 kayıtları; henüz yeni agent yok.

## Faz 2 — Kapanışı kanıta bağla ve kesintiden devamı güvenilir yap

**Öncelik:** P0. **Bağımlılık:** Faz 1.

**Hedef dosyalar:** `scripts/state-update.sh`, yeni `scripts/floor-guard.sh`, `hooks/pre-guard`, `hooks/auto-qa`, `hooks/session-start`, `skills/triage/references/flow-{light,full,direct}.md`, `skills/triage/references/templates.md`, `skills/se-status/SKILL.md`; `evals/suites/state/`, `evals/suites/scripts/` ve `evals/suites/hooks/`.

### İşler

- [x] `state-update.sh` içinde slice kapanışı için açık bir işlem tanımla; önerilen arayüz `--close-slice <id>`. Doğrulama kayıtlarını okuyup karar vermeden faz ilerletmesin. Roadmap olmayan planned slice için de çalışsın.
- [x] Genel key=value çağrısıyla `completed=true` veya ileri `current_phase` yazarak aynı kontrolün atlanmasını engelle. Bootstrap, roadmap genişletme ve tamamlanmış projeye milestone ekleme meşru geçişlerini ayrı ele al.
- [x] Roadmap, kapanış artifact'ı ve state arasındaki işlem sırasını idempotent tasarla. Çok dosyalı yazımı atomik ilan etme; her kesinti noktasından tekrar çağrı güvenli biçimde tamamlasın veya önceki durumu korusun.
- [ ] `.active` biçimi/kind/id doğrulamasını ekle. Planned marker geçerli plan ve plan revizyonuna bağlı olsun; direct/bootstrap yolları kendi sözleşmeleriyle devam etsin.
- [x] `.se/` yazımı, Bash üzerinden state değişimi ve git commit dahil kapanışa ulaşan yolları listele. Kapanış artifact'ı/roadmap-done commit'ine mevcut commit backstop üzerinden uygulanabilir tutarlılık kontrolü koy. Doğrudan yerel dosya yazabilen aktöre karşı mutlak güvenlik iddiasında bulunma.
- [x] `review skipped (tooling)` yolunu `incomplete` yap. Fail-open hook politikasıyla çelişkiyi açıkça çöz: bir hook host oturumunu kilitlemeyebilir, fakat eksik kanıt hiçbir kapanış işleminde başarıya çevrilmez.
- [x] Kullanıcı risk kabulünü belirli bulgu ve revizyona bağla. Sessiz `partial → done` kalksın. Kabulün yerel kaydını insan kimlik doğrulaması gibi sunma.
- [x] Resume sırasında izin marker'ını temizlemek ile tamamlanmamış işin ilerleme kaydını kaybetmeyi ayır. Kullanıcı kaldığı görevi ve eksik kontrolü görebilsin.
- [ ] Yeşile nasıl gelindiğini slice diff'i üzerinde denetleyen taban kontrolü ekle; önerilen `scripts/floor-guard.sh`, `hooks/auto-qa`'nın yeşil yolundan çağrılır. Aradığı beş hamle: eklenen suppression/ignore yorumu, eklenen atlama işareti (`.skip`, `xit`, `t.Skip` ve dengi), hayatta kalan test dosyalarından çıkarılan assertion, yeni boş `catch`/`pass`/stub gövdesi, gevşetilen eşik. Bulgu blocker'dır; kapanış politikasının mevcut blocker satırına düşer, sonuç sözleşmesine yeni boyut eklemez.
- [ ] Kontrolü diff üzerine kur, dil başına kural motoru yazma. Meşru durumlar (mevcut atlamanın taşınması, testin dosyasıyla birlikte silinmesi, spec gereği değişen eşik) Faz 2'nin açık risk kabulü yolundan geçsin; ikinci bir muafiyet mekanizması açma.

### Kabul ve kanıt

- [x] Review yok/bozuk/eski olduğunda doğrudan state-update, normal flow ve kapanış commit'i başarı üretmez.
- [ ] Reviewer yarıda kesildiğinde slice `incomplete` kalır; devam ettirilip doğru kayıt üretildiğinde kapanabilir.
- [x] `partial` açık risk kabulü olmadan ilerlemez; kabul sonrası eksik bulgu görünür kalır.
- [ ] Son fazın tamamlanması, ad-hoc planned slice, yeni milestone ve direct görev doğru çalışır.
- [ ] İşlem ortasında kesilip yeniden çağrıldığında faz iki kez ilerlemez; çelişkili roadmap/state sessizce korunmaz.
- [ ] `.active` bozukluğu veya jq/tooling eksikliği onaysız başarı kaydı yaratmaz; hata kullanıcıya gösterilir.
- [ ] Testi atlayarak, assertion silerek veya eşiği düşürerek yeşile gelen fixture slice kapanamaz; hangi hamle hangi dosyada yakalandı kullanıcıya gösterilir.
- [ ] Gerçek düzeltmeyle yeşile gelen slice yanlış pozitif üretmez; test eklemek, taşımak veya yeniden adlandırmak ihlal sayılmaz.

**Teslimat:** İki agent ile güvenilir tamamlanma. Faz 1–2 ayrı bir kullanılabilir sürüm dilimidir; sonraki deneyleri beklemez.

## Faz 3 — Reviewer rolünü ve red-proof çalışma ortamını ayır

**Öncelik:** P1. **Bağımlılık:** Faz 1–2.

> **Karar (2026-09-14): D5 iptal.** `red-proof.sh`'in geçici worktree yerine mevcut çalışma ağacında geri alma kararı kaldırıldı; gerekçesi `docs/specs/2026-09-07-red-proof.md` "Out of scope" bölümünde iptal işaretiyle duruyor. Worktree'nin bağımlılık sorunu artık bu fazın çözmesi gereken bir gereksinim, worktree'den kaçınma sebebi değil. Spec değişikliği uygulamadan önce gelir.

**Hedef dosyalar:** `scripts/red-proof.sh`, `agents/verifier.md`, `hooks/pre-guard`, `hooks/hooks.json` yalnızca gereken rol denetimi için, ilgili red-proof/hook eval'leri ve doğrulama dokümanları.

### İşler

- [x] Red-proof'u sabit kaynak revizyonundan hazırlanan geçici git worktree üzerinde çalıştır; ana checkout/index'i geri alma yöntemi kaldırılır. İzolasyonun bağımlılık/ignored dosya ihtiyacını açıkça çöz; keyfi kullanıcı ortamını kopyalama.
- [x] Runner/bağımlılık eksikliği, timeout ve test toplama/derleme hatasıyla gerçek assertion başarısızlığını ayırabildiği kadar raporla. Ayıramadığı yerde `inconclusive`; genel nonzero sonucu davranış kanıtı sayma.
- [x] Ana raporda red-proof'u “değişikliğe duyarlılık kontrolü” olarak adlandır. Tarihsel test-first iddiasını bu çıktıya dayandırma.
- [x] Verifier izin sözleşmesini tanımla: üretim kodunu düzeltmez; tanımlı rapor/bellek ve izole doğrulama alanı dışında yazmaz. Plugin-wide hook'un subagent kimliğiyle uygulanabilirliğini kurulu Claude Code üzerinde doğrula; plugin agent frontmatter'ına desteklenmeyen permissionMode/hooks ekleme.
- [x] Memory'nin açtığı araçlar ve Bash yazımları dahil gerçek runtime denemesi yap. Teknik olarak uygulanamayan sınırı dokümanda davranış sözleşmesi olarak açıkça belirt.
- [ ] Kısa `maxTurns` nedeniyle inceleme kesilmesini Faz 1'in incomplete sonucuna bağla; kapsam sayısını başarı kanıtı yerine inceleme envanteri olarak tut.

### Kabul ve kanıt

- [x] Başarılı, başarısız, timeout ve kesilmiş red-proof çalışması ana checkout/index'i değiştirmez.
- [x] Eksik bağımlılık, aynı dosyadaki test veya ayrılamayan kaynak/test yapısı yanlış kırmızı kanıt üretmez.
- [ ] Yanlış slice aralığı ve eski kaynak revizyonu reddedilir veya açıkça sonuçsuz kalır.
- [x] Gerçek Claude Code smoke senaryosunda reviewer kaynak düzeltmeye yönlendirildiğinde sınırın çalıştığı görülür; yalnızca araç listesinin metni denetlenmez.

**Teslimat:** İzole doğrulama ve doğru kapsamda bağımsız reviewer. Worktree yaşam döngüsü için ayrı runtime eklenmez.

## Faz 4 — Yeni rollerin değerini gerçek görevlerde ölç

**Öncelik:** P1. **Bağımlılık:** Faz 2; mutasyon içeren deneyler için Faz 3.

**Hedef dosyalar:** `evals/suites/behavioral/`, `evals/fixtures/behavioral/`, `evals/suites/behavioral/README.md`, `TESTING.md`; deney sonuçları için `docs/` altında kabul edilmiş kısa değerlendirme kaydı.

### İşler

- [ ] Küçük ama temsilî görev seti kur: net bug fix, muğlak özellik, çok dosyalı refactor, yetkilendirme/veri bütünlüğü, çok adımlı kullanıcı akışı, test runner bulunmayan repo.
- [ ] Düzeltilmiş iki-agent akışını baseline yap. Aynı görevleri baseline + bağımsız plan eleştirisi ve baseline + davranış tester'ı ile karşılaştır; her koşul temiz aynı başlangıç revizyonunu alsın.
- [ ] Başlangıçta rol talimatlarını deney fixture'ında tut; sırf denemek için production agents listesine ekleme.
- [ ] Her koşulu en az üç kez çalıştır; model kimliği, effort, Claude Code sürümü, başlangıç commit'i, senaryo ve ham sonuçları kaydet. Eksik kullanım verisini sıfır diye raporlama.
- [ ] Ölçümün maliyetini önden yaz: altı görev × üç koşul × üç tekrar, agent koşusu başına gerçek token/süre. Bütçe kabul edilmeden deney başlamaz; sığmıyorsa koşu sayısı değil görev seti daraltılır, çünkü tek koşu gürültüyü ölçemez.
- [ ] Gizli kabul kontrolleri ve önceden belirlenmiş kusurları ölçümde kullan. Agent'in kendi “başardım” açıklamasını başarı skoru sayma.
- [ ] Yanlış done, atlanan kriter, uygulamadan önce bulunan yanlış varsayım, kaçan hata, yanlış pozitif bulgu, kullanıcı müdahalesi, gereksiz soru, süre ve kullanım değerlerini ayrı raporla.

### Kabul ve karar kapısı

- [ ] Sonuç başka bir geliştiricinin yeniden çalıştırabileceği komutlarla ve ham çıktıyla desteklenir.
- [ ] Küçük örneklem evrensel üstünlük iddiasına dönüştürülmez; görev türü bazında sonuç ve belirsizlik gösterilir.
- [ ] Bir rol sadece daha uzun rapor ürettiği için kabul edilmez. Hangi kaçan hatayı yakaladığı ve hangi ek maliyeti getirdiği görünürdür.
- [ ] Kalıcılaştırma kararı kullanıcıyla sonuç tablosu üzerinden verilir. Fayda göstermeyen rol kaldırılır; bu deneyin başarılı bir sonucudur.

**Teslimat:** Rol bazında devam/çıkar kararı. Bu fazın ölçüm işi kapsam dahilindedir; sonraki kalıcı rol değişiklikleri bu karara bağlıdır.

## Faz 5 — Kanıtlanan rolleri koşullu olarak ürünleştir

**Öncelik:** P2, koşullu. **Bağımlılık:** Faz 4'te ilgili rolün kabulü.

**Hedef dosyalar:** Gerekirse yeni `agents/plan-critic.md` ve/veya `agents/tester.md`; `skills/triage/SKILL.md`, `skills/triage/references/flow-{light,full}.md`, `agents/executor.md`, `agents/verifier.md`, agent/frontmatter eval'leri. Dosya eklemek otomatik kabul edilmiş karar değildir.

### İşler

- [ ] Plan eleştirmeni uygulanacaksa yalnızca spec/plan/repo tutarsızlıkları, eksik kriterler ve önemli riskleri raporlasın; planı yeniden yazmasın. Sorularını ana agent kullanıcıya taşısın.
- [ ] Tester uygulanacaksa spec'ten bağımsız senaryolar çıkarsın ve gerçek davranışı sınasın; üretim kodunu ve executor'ın testlerini değiştirmesin. Kalıcı regresyon gerekiyorsa bulguyu executor uygulasın.
- [ ] Roller için girdiyi açıklaştır: kullanıcı hedefi, spec/plan yolu ve revizyonu, kapsam, kaynak aralığı, çalıştırılabilir komutlar, bilinen ortam engelleri. Ana konuşma geçmişinin otomatik aktarıldığını varsayma.
- [ ] Rol tetiklerini ölçümün desteklediği risk/senaryolara bağla. Her işe sabit agent zinciri veya kullanıcıya mode seçimi ekleme.
- [ ] Ana agent tek karar/koordinasyon sahibi, mevcut kapanış işlemi tek sonuç tüketicisi kalsın. Yeni roller için paralel ikinci verdict sistemi kurma.
- [ ] “Tam iki agent” yapısal eval'ini yeni kabul edilmiş rol sözleşmesine geçir; yeni agent sayısını kalite metriği yapma.

### Kabul ve kanıt

- [ ] Basit görev gereksiz rol çağırmaz; hedeflenen riskli görev ilgili rolü çağırır.
- [ ] Plan eleştirisi implementasyondan önce gerçek bir yanlış varsayımı yakalar.
- [ ] Tester green-suite arkasındaki hazırlanmış davranış hatasını yakalar ve düzeltmeyi executor'a bırakır.
- [ ] Rolün kesilmesi veya çelişkili sonucu kaybolmaz; kapsam için gerekliyse kapanışı incomplete yapar.

**Teslimat:** Faydası gösterilmiş, gerektiğinde çalışan uzman roller; kurum organizasyon şemasının agent kopyası değil.

## Faz 6 — Bağımsız dilimlerde kontrollü paralel executor

**Öncelik:** P2, koşullu. **Bağımlılık:** Faz 3 ve gerçek kullanımda paralelleştirilebilir iş ihtiyacı. Faz 5'in başarılı olması şart değildir.

**Hedef dosyalar:** `agents/executor.md`, triage flow/template dosyaları, state/marker ve doğrulama tüketicileri, worktree-aware davranış eval'leri. Yeni coordinator agent veya Agent Teams bağımlılığı yok.

### İşler

- [ ] Plan task'larına yalnızca paralel çalışacak dilimler için bağımlılık, dosya sahipliği ve entegrasyon sırası ekle. Aynı dosyayı değiştiren ya da birbirinin çıktısını bekleyen işleri paralel ilan etme.
- [ ] Aynı executor tanımından ayrı instance'lar kullan; her biri benzersiz slice id, sabit base/source revizyonu ve ayrı çalışma ağacı alsın.
- [ ] `.active`, progress, `.fixing` ve doğrulama sonuçlarının worktree/slice kapsamını netleştir. Aynı checkout'ta iki yazıcı başlatma.
- [ ] Ana agent entegrasyonu sıralı yürütür; git çatışması otomatik başarılı sayılmaz. Birleştirilmiş kaynak üzerinde mekanik kontrol ve final review yeniden yapılır.
- [ ] Bir dilim engellendiğinde bağımsız dilimler sürebilir; bağımlı dilim başlayamaz. Kapanış sadece entegre revizyonun kanıtıyla gerçekleşir.
- [ ] İptal/kesinti sonrası kullanıcı veya başka agent değişikliklerini silmeyen worktree yaşam döngüsü uygula.

### Kabul ve kanıt

- [ ] İki bağımsız dilim gerçekten eşzamanlı çalışır; marker/progress/review kayıtları çakışmaz.
- [ ] Bağımlı görev erken başlamaz, aynı-dosya çatışması sıralanır veya açıkça durur.
- [ ] Tekil dilimler yeşilken entegrasyon hatası içeren fixture kapanamaz.
- [ ] Bir worker iptal edildiğinde diğerinin kaynakları veya kanıtı kaybolmaz.

**Teslimat:** Aynı güvenilir kapanış sözleşmesini kullanan, dar kapsamlı paralellik. İhtiyaç gösterilemiyorsa bu faz uygulanmaz; iki-agent sürüm bunun yüzünden beklemez.

## Riskler

Biçim repo'nun plan şablonundan: `<risk> — <karşılık> — confirm: yes|no`. `confirm: yes`, uygulamadan önce kullanıcıya açıkça sorulur.

- **Sonuç sözleşmesi tek geçişte değişir; yarım kalan geçiş eski ve yeni alanı birlikte okuyan iki karar yolu bırakır.** Faz 1 tek revert'le geri alınabilen tek dilim olarak yürütülür; eski alan adlarını okuyan kod kalmadığı eval'le sabitlenir — confirm: no
- **Faz 3 izolasyonu, D5'in kaçındığı bağımlılık sorununu geri getirir.** Kurulu bağımlılığı olmayan worktree'de Check yanlış kırmızı verir ve reviewer var olmayan bir kapsam boşluğu bildirir. Ayrılamayan durumda sonuç `inconclusive`; bağımlılık hazırlanamıyorsa red-proof kendini devre dışı bırakır ve bunu kayda geçer, sessizce geçmez — confirm: yes (D5'in tersine çevrilmesi)
- **Kapanış sıkılaşınca test runner'ı olmayan meşru proje hiç kapanamaz hale gelir.** Prompt ve doküman repoları bu plugin'in gerçek kullanıcısı. `not_run` + reviewer değerlendirmesi yolu runner'sız fixture üzerinde sınanır; o yol kapanışı mümkün kılmıyorsa Faz 2 kabul edilmez — confirm: no
- **Faz 4 küçük örneklemde gürültüye boğulur ve karar üretmez.** Sonuçsuzluk da karardır: rol kalıcılaşmaz. Koşu sayısını artırmak yerine görev seti daraltılır — confirm: no
- **Faz 5 mevcut talimat bütçesine sığmıyor.** Ölçüldü (2026-09-15, Faz 1 sonrası): `agents/` + `skills/` = 47324 / 49152 byte, **1828 byte boş**; mevcut iki agent 5404 ve 8244 byte. Faz 1 tek başına 1505 byte yedi, yani boşluk her fazda daralıyor. İki yeni rol en iyimser tahminle 8 KB ister, üstüne triage ve flow eklemeleri gelir. Faz 5'e girmeden önce üçünden biri açıkça seçilir — bütçeyi yükselt (sayı bizim), mevcut prompt'lardan kes, ya da rolü agent yerine skill olarak yaz — confirm: yes
- **Altı faz, v5'in sade omurgasını büyütür.** Hard Rule 9 sınavından geçmeden eklenen her talimat bir sonraki model yükseltmesinde çift iş çıkarır. Her prompt eklemesi compensation/preference olarak sınıflandırılır; compensation olan, kendi davranışsal eval fixture'ıyla birlikte gelir — confirm: no

## Uygulama ve doğrulama düzeni

1. Her fazda hedef kaynakları ve ilgili eval'leri yeniden oku; önemli kararları uygulamadan önce ilgili spec'e bağla. Bu plan mevcut accepted spec'leri sessizce geçersiz kılmaz.
2. Prompt değişikliğinde `.agents/writing-for-agents.md` ve skill-mechanics eşlikçisini uygula. Rol sözleşmesini genel “daha dikkatli ol” metniyle büyütme.
3. Davranış değişikliği için somut başarısız fixture/smoke senaryosu oluştur; düzeltmeden sonra aynı senaryoyu çalıştır. Salt alan kopyalama veya kelime varlığı için test ekleme.
4. Bağımsız implementasyon ve fixture sahiplikleri varsa paralel çalıştır; aynı dosya ve sözleşme değişimini tek entegrasyon sahibi yönetir. Çalışan agent'ler birbirlerinin yarım değişikliklerinde tüm suite'i çalıştırmaz.
5. Faz entegrasyonunda `bash evals/run.sh` çalıştır. Davranışsal değerlendirmeler opt-in kalır; deterministic CI ile model kalite deneyi birbirine karıştırılmaz.
6. Her davranış fazını geçici gerçek projede `claude --plugin-dir /absolute/path/to/software-engineer` ile doğrula. Özellikle reviewer kesintisi, runner yokluğu, kısmi sonuç ve devam etme yollarını uygula; yalnızca shell eval yeşili plugin entegrasyonu sayılmaz.
7. Doğrulanmış fazın kapanışında ilgili README/STATE/DEVELOPMENT/TESTING/CHANGELOG ve örnekleri güncelle; deneme dosyalarını temizle. Tarihsel tasarım anlatımını tarihsel olarak koru. Atomik conventional commit'ler uygula; plan yazımı kendi başına commit başlatmaz.

## Öncelik ve ilerleme kararı

| Dilim | Fazlar | Çıkış koşulu |
|---|---|---|
| Güvenilir temel | 1–2 | Eksik kanıtla yanlış done yok; kesinti sonrası devam ve eski kayıtların davranışı açık. |
| Bağımsız doğrulama | 3 | Ana checkout değişmeden red-proof; gerçek runtime'da sınırları denenmiş verifier. |
| Rol kararı | 4 | Tekrarlanabilir görev sonuçları ve kullanıcıyla devam/çıkar kararı. |
| Seçici uzmanlaşma | 5 | Yalnızca faydası gösterilen roller, risk temelli çağrı. |
| Paralel uygulama | 6 | İzole dilimler ve entegre revizyon üzerinden kapanış. |

### Açık adayların dağılımı

Mimari review'ın dokuz adayı (C1–C9) ve dış survey'in üç fikri (A1–A3) bu fazlara dağılır. Kapsam dışı olanlar unutulmuş değil, ayrı iş.

| Aday | Nerede |
|---|---|
| C1 — `.se/.active`'e yazıcı modülü | Faz 2, `.active` biçim/kind doğrulaması |
| C2 — plan formatı için tek parser | Faz 1, `verify-phase.sh` elden geçerken |
| C3 — slice base'ini veri olarak kaydet | Faz 1, plan blob kimliği ve kaynak commit aralığı |
| C5 — "managed" için tek predicate | Faz 2, state ve `pre-guard` yolları |
| C6 — `write_targets`'ı adreslenebilir yap | Faz 2, kapanışa ulaşan yolların listesi |
| C7 — Tier-1 kaydının sahibini netleştir | Faz 1 |
| C8 — Tier-2 kaydına yazıcı | Faz 1 |
| C9 — eval gate'ini flow'lara yönelt | Faz 1, davranışı sına maddesi |
| A1 — taban kontrolü (floor guard) | Faz 2 |
| A3 — arm öncesi temiz baseline | Faz 3, izolasyon bu sorunu yeniden tanımlıyor |
| C4 — `detect-quality` test komutunu `detect-test`'ten alsın | **Kapsam dışı.** Bağımsız defect: Makefile-only projede `CLAUDE.md` "test komutu yok" derken `auto-qa` `make test` çalıştırıp blokluyor. Bu planı beklemez. |
| A2 — mevcut ADR konvansiyonunu tespit et | **Kapsam dışı.** `skills/adr` yalnızca charter ile `.se/adr/` arasında dallanıyor; `docs/adr/` olan projede paralel şema açıyor. Bu planın hiçbir fazına dokunmuyor. |

**İlk uygulanacak iş:** Faz 1'in sonuç sözleşmesini spec'e bağlamak; runner-yok ve eksik-review baseline'ını kurmak. Runner-yok tarafı sıfırdan yazılmaz — `evals/fixtures/repos/no-tests/` mevcut ve bugünkü yanlış `pass` kaydı onun üzerinde üretilebiliyor. Yeni planner/tester dosyası açmak değil.

## Kaynaklar

- Mevcut v5 karar kaydı: `docs/specs/2026-09-04-playbook-architecture.md`.
- Red-proof karar kaydı: `docs/specs/2026-09-07-red-proof.md`.
- Claude Code subagents: https://code.claude.com/docs/en/sub-agents
- Memory ve araç erişimi: https://code.claude.com/docs/en/sub-agents#enable-persistent-memory
- Hook olayları: https://code.claude.com/docs/en/hooks
- Agent Teams ve trade-off'lar: https://code.claude.com/docs/en/agent-teams
- AI-native SDLC: https://claude.com/blog/the-ai-native-sdlc-playbook

Platform davranışları değişebilir; uygulama smoke testlerinde kullanılan Claude Code sürümü kaydedilir. Araştırma sırasında yerel CLI sürümü `2.1.270` idi.
