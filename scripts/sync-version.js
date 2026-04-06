#!/usr/bin/env node

import fs from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

const packageJsonPath = path.join(__dirname, '../package.json')
const tauriConfPath = path.join(__dirname, '../src-tauri/tauri.conf.json')
const cargoTomlPath = path.join(__dirname, '../src-tauri/Cargo.toml')

const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'))
const tauriConf = JSON.parse(fs.readFileSync(tauriConfPath, 'utf8'))
let cargoToml = fs.readFileSync(cargoTomlPath, 'utf8')

const version = packageJson.version

if (tauriConf.version !== version) {
  tauriConf.version = version
  fs.writeFileSync(tauriConfPath, JSON.stringify(tauriConf, null, 2) + '\n')
}

const cargoVersionRegex = /^version = "(.+?)"$/m
const cargoMatch = cargoToml.match(cargoVersionRegex)
const cargoVersion = cargoMatch ? cargoMatch[1] : null

if (cargoVersion !== version) {
  cargoToml = cargoToml.replace(cargoVersionRegex, `version = "${version}"`)
  fs.writeFileSync(cargoTomlPath, cargoToml)
}

if (tauriConf.version !== version || cargoVersion !== version) {
  console.log(`Synced version to ${version}`)
} else {
  console.log(`Version already synced (${version})`)
}
