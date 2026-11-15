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
//
// Загрузка сборки — tools/upload_testflight.sh (xcodebuild archive + export с destination=upload, тот же ключ).
// Отправка версии на проверку в App Store — только с подтверждения пользователя (команды пока нет).
//
// Ключ: ~/.littlebite-keys/AuthKey_<KEY_ID>.p8 (создаёт пользователь, вне git, не читать и не печатать).
// KEY_ID и ISSUER_ID — не секреты. Роль ключа — App Manager.

import { createPrivateKey, sign } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'

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
