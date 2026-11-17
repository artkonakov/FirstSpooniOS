#!/usr/bin/env node
// App Store Connect API для «Ложку за маму» (app.littlebite). Без зависимостей: Node 18+ (fetch, crypto).
//
//   node tools/asc_api.mjs apps                         приложения аккаунта (проверка ключа)
//   node tools/asc_api.mjs builds [--limit 10]          последние сборки: версия, номер, обработка, срок TestFlight
//   node tools/asc_api.mjs whats-new <номер> "<текст>"  «Что тестировать» (ru) для сборки TestFlight
//   node tools/asc_api.mjs groups                       группы TestFlight
//   node tools/asc_api.mjs add-to-group <номер> <группа> выдать сборку группе тестировщиков (имя или id)
//   node tools/asc_api.mjs versions                     версии App Store и их состояние
//   node tools/asc_api.mjs listing                      тексты страницы App Store (по языкам)
//   node tools/asc_api.mjs version-create <1.1>         новая версия App Store (в подготовке), если её ещё нет
//   node tools/asc_api.mjs listing-set [store/appstore.ru.json] [--version 1.1]   залить тексты: имя, подзаголовок,
//                                                       описание, промо-текст, ключевые слова, ссылки. Язык — поле
//                                                       locale в файле (ru, en-US — store/appstore.en.json); нет такой
//                                                       локализации — создаётся. Если имя занято — пробует nameFallback.
//   node tools/asc_api.mjs screenshots [store/screenshots] [--locale ru|en-US] [--version 1.1]
//                                                       заменить скриншоты версии: папки iphone/ (6.9") и ipad/ (13"),
//                                                       PNG по порядку имён (01-…, 02-…); en — store/screenshots-en
//   Без --version берётся версия в подготовке (а если её нет — ожидающая проверки).
//
// Загрузка сборки — tools/upload_testflight.sh (xcodebuild archive + export с destination=upload, тот же ключ).
//   node tools/asc_api.mjs submit <номер сборки> --yes  привязать сборку к версии в подготовке и отправить на проверку
//                                                       App Store — ТОЛЬКО с подтверждения пользователя
//
// Ключ: ~/.littlebite-keys/AuthKey_<KEY_ID>.p8 (создаёт пользователь, вне git, не читать и не печатать).
// KEY_ID и ISSUER_ID — не секреты. Роль ключа — App Manager.

import { createHash, createPrivateKey, sign } from 'node:crypto'
import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs'
import { homedir } from 'node:os'
import { basename, join } from 'node:path'

export const KEY_ID = 'A2VCF6W9QB'
export const ISSUER_ID = 'd7cee3e8-50f7-4cfb-bf4f-d3127e6a691a'
export const KEY_PATH = join(homedir(), '.littlebite-keys', `AuthKey_${KEY_ID}.p8`)
const BUNDLE_ID = 'app.littlebite'
const API = 'https://api.appstoreconnect.apple.com'

const b64url = (b) => Buffer.from(b).toString('base64url')

function token() {
  const now = Math.floor(Date.now() / 1000)
  const header = b64url(JSON.stringify({ alg: 'ES256', kid: KEY_ID, typ: 'JWT' }))
  const payload = b64url(JSON.stringify({ iss: ISSUER_ID, iat: now, exp: now + 15 * 60, aud: 'appstoreconnect-v1' }))
  const key = createPrivateKey(readFileSync(KEY_PATH))
  const sig = sign('sha256', Buffer.from(`${header}.${payload}`), { key, dsaEncoding: 'ieee-p1363' })
  return `${header}.${payload}.${b64url(sig)}`
}

let jwt
async function api(method, path, body) {
  jwt ??= token()
  const res = await fetch(API + path, {
    method,
    headers: { Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  })
  const text = await res.text()
  const json = text ? JSON.parse(text) : {}
  if (!res.ok) {
    const errs = (json.errors ?? []).map((e) => `${e.status} ${e.code}: ${e.detail ?? e.title}`).join('\n')
    throw new Error(`${method} ${path} → ${res.status}\n${errs || text}`)
  }
  return json
}
const get = (p) => api('GET', p)

async function appId() {
  const r = await get(`/v1/apps?filter[bundleId]=${BUNDLE_ID}`)
  const app = r.data.find((a) => a.attributes.bundleId === BUNDLE_ID)
  if (!app) throw new Error(`Приложение ${BUNDLE_ID} не найдено в App Store Connect`)
  return app.id
}

async function buildByNumber(app, number) {
  const r = await get(`/v1/builds?filter[app]=${app}&filter[version]=${encodeURIComponent(number)}&include=preReleaseVersion`)
  const b = r.data[0]
  if (!b) throw new Error(`Сборка с номером ${number} не найдена (ещё обрабатывается? см. builds)`)
  return b
}


/** Версия App Store, которую ещё можно править (в подготовке / отклонена разработчиком). */
async function editableVersion(app) {
  const r = await get(`/v1/apps/${app}/appStoreVersions?filter[platform]=IOS&limit=10`)
  const state = (x) => x.attributes.appStoreState ?? x.attributes.appVersionState
  const wanted = arg('--version')
  if (wanted) {
    const v = r.data.find((x) => x.attributes.versionString === wanted)
    if (!v) throw new Error(`Версии ${wanted} нет — создайте: version-create ${wanted}`)
    return v
  }
  // Сначала то, что точно можно править, и только потом — ожидающая проверки.
  for (const ok of [['PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED', 'METADATA_REJECTED'], ['WAITING_FOR_REVIEW']]) {
    const v = r.data.find((x) => ok.includes(state(x)))
    if (v) return v
  }
  throw new Error('Нет версии в подготовке — создайте её: version-create <номер>')
}

async function versionLocalization(version, locale) {
  const r = await get(`/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations`)
  return r.data.find((l) => l.attributes.locale === locale) ?? (await api('POST', '/v1/appStoreVersionLocalizations', {
    data: { type: 'appStoreVersionLocalizations', attributes: { locale },
      relationships: { appStoreVersion: { data: { type: 'appStoreVersions', id: version.id } } } },
  })).data
}

/** Тип скриншотов App Store Connect для папки. */
const SCREENSHOT_TYPES = { iphone: 'APP_IPHONE_67', ipad: 'APP_IPAD_PRO_3GEN_129' }

const arg = (name, def) => {
  const i = process.argv.indexOf(name)
  return i > 0 ? process.argv[i + 1] : def
}

const commands = {
  async apps() {
    const r = await get('/v1/apps?fields[apps]=name,bundleId,sku,primaryLocale')
    for (const a of r.data) console.log(`${a.id}  ${a.attributes.bundleId}  ${a.attributes.name}  (${a.attributes.primaryLocale})`)
  },

  async builds() {
    const app = await appId()
    const limit = arg('--limit', '10')
    const r = await get(`/v1/builds?filter[app]=${app}&sort=-uploadedDate&limit=${limit}&include=preReleaseVersion`)
    const versions = Object.fromEntries((r.included ?? []).map((v) => [v.id, v.attributes.version]))
    if (!r.data.length) console.log('Сборок нет')
    for (const b of r.data) {
      const a = b.attributes
      const v = versions[b.relationships?.preReleaseVersion?.data?.id] ?? '?'
      console.log(`${v} (${a.version})  ${a.processingState}  загружена ${a.uploadedDate?.slice(0, 16)}` +
        `${a.expired ? '  истекла' : `  до ${a.expirationDate?.slice(0, 10)}`}`)
    }
  },

  async 'whats-new'(number, text) {
    if (!number || !text) throw new Error('whats-new <номер сборки> "<текст>"')
    const build = await buildByNumber(await appId(), number)
    const r = await get(`/v1/builds/${build.id}/betaBuildLocalizations`)
    const ru = r.data.find((l) => l.attributes.locale === 'ru')
    if (ru) await api('PATCH', `/v1/betaBuildLocalizations/${ru.id}`, {
      data: { type: 'betaBuildLocalizations', id: ru.id, attributes: { whatsNew: text } },
    })
    else await api('POST', '/v1/betaBuildLocalizations', {
      data: { type: 'betaBuildLocalizations', attributes: { locale: 'ru', whatsNew: text },
        relationships: { build: { data: { type: 'builds', id: build.id } } } },
    })
    console.log(`«Что тестировать» для сборки ${number} обновлено`)
  },

  async groups() {
    const app = await appId()
    const r = await get(`/v1/apps/${app}/betaGroups`)
    if (!r.data.length) console.log('Групп нет — создать в App Store Connect → TestFlight')
    for (const g of r.data) {
      const a = g.attributes
      console.log(`${g.id}  ${a.name}  ${a.isInternalGroup ? 'внутренняя' : 'внешняя'}${a.publicLinkEnabled ? `  ${a.publicLink}` : ''}`)
    }
  },

  async 'add-to-group'(number, group) {
    if (!number || !group) throw new Error('add-to-group <номер сборки> <имя или id группы>')
    const app = await appId()
    const groups = (await get(`/v1/apps/${app}/betaGroups`)).data
    const g = groups.find((x) => x.id === group || x.attributes.name === group)
    if (!g) throw new Error(`Группа «${group}» не найдена: ${groups.map((x) => x.attributes.name).join(', ')}`)
    const build = await buildByNumber(app, number)
    await api('POST', `/v1/betaGroups/${g.id}/relationships/builds`, { data: [{ type: 'builds', id: build.id }] })
    console.log(`Сборка ${number} выдана группе «${g.attributes.name}»`)
  },

  async versions() {
    const app = await appId()
    const r = await get(`/v1/apps/${app}/appStoreVersions?include=build`)
    const builds = Object.fromEntries((r.included ?? []).map((b) => [b.id, b.attributes.version]))
    if (!r.data.length) console.log('Версий нет')
    for (const v of r.data) {
      const a = v.attributes
      const b = builds[v.relationships?.build?.data?.id]
      console.log(`${a.versionString}  ${a.appStoreState ?? a.appVersionState}  ${a.platform}${b ? `  сборка ${b}` : '  без сборки'}`)
    }
  },

  async 'listing-set'(file = 'store/appstore.ru.json') {
    const t = JSON.parse(readFileSync(file, 'utf8'))
    const app = await appId()
    // Имя, подзаголовок, политика — appInfo (редактируемый, если их несколько).
    const infos = (await get(`/v1/apps/${app}/appInfos`)).data
    const info = infos.find((i) => i.attributes.appStoreState !== 'READY_FOR_SALE') ?? infos[0]
    const attrs = (name) => ({ name, subtitle: t.subtitle, privacyPolicyUrl: t.privacyPolicyUrl })
    let infoLoc = (await get(`/v1/appInfos/${info.id}/appInfoLocalizations`)).data.find((l) => l.attributes.locale === t.locale)
    // Имя может быть занято другим приложением — тогда запасное (nameFallback).
    for (const name of [t.name, t.nameFallback].filter(Boolean)) {
      try {
        if (infoLoc) {
          await api('PATCH', `/v1/appInfoLocalizations/${infoLoc.id}`, { data: { type: 'appInfoLocalizations', id: infoLoc.id, attributes: attrs(name) } })
        } else {
          infoLoc = (await api('POST', '/v1/appInfoLocalizations', { data: { type: 'appInfoLocalizations',
            attributes: { locale: t.locale, ...attrs(name) }, relationships: { appInfo: { data: { type: 'appInfos', id: info.id } } } } })).data
        }
        console.log(`appInfo [${t.locale}]: имя «${name}», подзаголовок, политика конфиденциальности`)
        break
      } catch (e) {
        if (name === t.nameFallback || !t.nameFallback || !/name|NAME/.test(e.message)) throw e
        console.log(`имя «${name}» не принято (${e.message.split('\n').pop()}) — пробую «${t.nameFallback}»`)
      }
    }
    const version = await editableVersion(app)
    const loc = await versionLocalization(version, t.locale)
    await api('PATCH', `/v1/appStoreVersionLocalizations/${loc.id}`, { data: { type: 'appStoreVersionLocalizations', id: loc.id,
      attributes: { description: t.description, keywords: t.keywords, promotionalText: t.promotionalText,
        supportUrl: t.supportUrl, marketingUrl: t.marketingUrl } } })
    console.log(`версия ${version.attributes.versionString} [${t.locale}]: описание ${t.description.length} симв., ключевые слова ${t.keywords.length}/100`)
  },

  async 'version-create'(versionString) {
    if (!versionString) throw new Error('version-create <номер версии, например 1.1>')
    const app = await appId()
    const r = await get(`/v1/apps/${app}/appStoreVersions?filter[platform]=IOS&limit=20`)
    const existing = r.data.find((x) => x.attributes.versionString === versionString)
    if (existing) {
      console.log(`версия ${versionString} уже есть: ${existing.attributes.appStoreState ?? existing.attributes.appVersionState}`)
      return
    }
    const v = (await api('POST', '/v1/appStoreVersions', { data: { type: 'appStoreVersions',
      attributes: { platform: 'IOS', versionString }, relationships: { app: { data: { type: 'apps', id: app } } } } })).data
    console.log(`создана версия ${versionString}: ${v.attributes.appStoreState ?? v.attributes.appVersionState}`)
  },

  async screenshots(dir = 'store/screenshots') {
    const app = await appId()
    const version = await editableVersion(app)
    const loc = await versionLocalization(version, arg('--locale', 'ru'))
    const sets = (await get(`/v1/appStoreVersionLocalizations/${loc.id}/appScreenshotSets`)).data
    for (const [folder, type] of Object.entries(SCREENSHOT_TYPES)) {
      const path = join(dir, folder)
      if (!existsSync(path)) { console.log(`${folder}: папки нет — пропуск`); continue }
      const files = readdirSync(path).filter((f) => f.endsWith('.png')).sort()
      if (!files.length) continue
      let set = sets.find((x) => x.attributes.screenshotDisplayType === type)
      if (set) {
        for (const old of (await get(`/v1/appScreenshotSets/${set.id}/appScreenshots`)).data) await api('DELETE', `/v1/appScreenshots/${old.id}`)
      } else {
        set = (await api('POST', '/v1/appScreenshotSets', { data: { type: 'appScreenshotSets', attributes: { screenshotDisplayType: type },
          relationships: { appStoreVersionLocalization: { data: { type: 'appStoreVersionLocalizations', id: loc.id } } } } })).data
      }
      for (const f of files) {
        const bytes = readFileSync(join(path, f))
        const shot = (await api('POST', '/v1/appScreenshots', { data: { type: 'appScreenshots',
          attributes: { fileName: f, fileSize: statSync(join(path, f)).size },
          relationships: { appScreenshotSet: { data: { type: 'appScreenshotSets', id: set.id } } } } })).data
        for (const op of shot.attributes.uploadOperations) {
          const headers = Object.fromEntries(op.requestHeaders.map((h) => [h.name, h.value]))
          const res = await fetch(op.url, { method: op.method, headers, body: bytes.subarray(op.offset, op.offset + op.length) })
          if (!res.ok) throw new Error(`загрузка ${f}: HTTP ${res.status}`)
        }
        await api('PATCH', `/v1/appScreenshots/${shot.id}`, { data: { type: 'appScreenshots', id: shot.id,
          attributes: { uploaded: true, sourceFileChecksum: createHash('md5').update(bytes).digest('hex') } } })
        console.log(`${folder} ${type}: ${f}`)
      }
    }
  },

  async submit(number) {
    if (!number || !process.argv.includes('--yes')) throw new Error('submit <номер сборки> --yes (только с подтверждения пользователя)')
    const app = await appId()
    const version = await editableVersion(app)
    const build = await buildByNumber(app, number)
    if (build.attributes.processingState !== 'VALID') throw new Error(`сборка ${number}: ${build.attributes.processingState}`)
    await api('PATCH', `/v1/appStoreVersions/${version.id}/relationships/build`, { data: { type: 'builds', id: build.id } })
    console.log(`версия ${version.attributes.versionString}: сборка ${number}`)
    // Открытая (не отправленная) заявка на проверку или новая.
    const open = (await get(`/v1/reviewSubmissions?filter[app]=${app}&filter[platform]=IOS&filter[state]=READY_FOR_REVIEW`)).data[0]
    const sub = open ?? (await api('POST', '/v1/reviewSubmissions', { data: { type: 'reviewSubmissions',
      attributes: { platform: 'IOS' }, relationships: { app: { data: { type: 'apps', id: app } } } } })).data
    const items = (await get(`/v1/reviewSubmissions/${sub.id}/items`)).data
    if (!items.length) {
      await api('POST', '/v1/reviewSubmissionItems', { data: { type: 'reviewSubmissionItems', relationships: {
        reviewSubmission: { data: { type: 'reviewSubmissions', id: sub.id } },
        appStoreVersion: { data: { type: 'appStoreVersions', id: version.id } } } } })
    }
    const done = await api('PATCH', `/v1/reviewSubmissions/${sub.id}`, { data: { type: 'reviewSubmissions', id: sub.id, attributes: { submitted: true } } })
    console.log(`отправлено на проверку: ${done.data.attributes.state}`)
  },

  async listing() {
    const app = await appId()
    const infos = await get(`/v1/apps/${app}/appInfos`)
    for (const info of infos.data) {
      const locs = await get(`/v1/appInfos/${info.id}/appInfoLocalizations`)
      for (const l of locs.data) console.log(`[${l.attributes.locale}] имя: ${l.attributes.name}; подзаголовок: ${l.attributes.subtitle ?? '—'}`)
    }
    const versions = await get(`/v1/apps/${app}/appStoreVersions?limit=1`)
    for (const v of versions.data) {
      const locs = await get(`/v1/appStoreVersions/${v.id}/appStoreVersionLocalizations`)
      for (const l of locs.data) {
        const a = l.attributes
        console.log(`[${a.locale}] ${v.attributes.versionString}: описание ${a.description?.length ?? 0} симв., ` +
          `ключевые слова: ${a.keywords ?? '—'}, поддержка: ${a.supportUrl ?? '—'}`)
      }
    }
  },
}

const [cmd, ...rest] = process.argv.slice(2)
if (!commands[cmd]) {
  console.log(readFileSync(new URL(import.meta.url), 'utf8').split('\n').filter((l) => l.startsWith('//')).join('\n'))
  process.exit(cmd ? 1 : 0)
}
commands[cmd](...rest.filter((x) => !x.startsWith('--'))).catch((e) => {
  console.error(e.message)
  process.exit(1)
})
