import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { execFile as execFileCallback } from 'node:child_process';
import { promisify } from 'node:util';

const REVISION = '7e720a3de062059d4c5400a379146a601d9010e0';
const BASE_URL = `https://raw.githubusercontent.com/ofrohn/d3-celestial/${REVISION}/data`;
const ROOT = path.resolve(import.meta.dirname, '..');
const GENERATED_FILE = path.join(ROOT, 'entry/src/main/ets/data/GeneratedSkyCatalog.ets');
const LINES_FILE = path.join(ROOT, 'entry/src/main/resources/rawfile/normal_sky_lines.json');
const execFile = promisify(execFileCallback);

async function loadJson(name) {
  let lastError;
  for (let attempt = 1; attempt <= 2; attempt++) {
    try {
      const response = await fetch(`${BASE_URL}/${name}`, {
        headers: { 'User-Agent': 'StarFinding-catalog-importer' }
      });
      if (!response.ok) {
        throw new Error(`${response.status} ${response.statusText}`);
      }
      return await response.json();
    } catch (error) {
      lastError = error;
      await new Promise(resolve => setTimeout(resolve, attempt * 800));
    }
  }
  try {
    const endpoint = `repos/ofrohn/d3-celestial/contents/data/${name}?ref=${REVISION}`;
    const result = await execFile('gh', [
      'api', endpoint, '-H', 'Accept: application/vnd.github.raw+json'
    ], { maxBuffer: 8 * 1024 * 1024 });
    return JSON.parse(result.stdout);
  } catch (ghError) {
    throw new Error(`无法下载 ${name}: ${lastError}; GitHub CLI: ${ghError}`);
  }
}

function normalizeLongitude(longitude) {
  const normalized = longitude % 360;
  return normalized < 0 ? normalized + 360 : normalized;
}

function adjustLongitude(longitude, reference) {
  let adjusted = longitude;
  while (adjusted - reference > 180) adjusted -= 360;
  while (adjusted - reference < -180) adjusted += 360;
  return adjusted;
}

function pointInRing(longitude, latitude, ring) {
  let inside = false;
  for (let index = 0, previous = ring.length - 1; index < ring.length; previous = index++) {
    const currentX = adjustLongitude(Number(ring[index][0]), longitude);
    const previousX = adjustLongitude(Number(ring[previous][0]), longitude);
    const currentY = Number(ring[index][1]);
    const previousY = Number(ring[previous][1]);
    const intersects = (currentY > latitude) !== (previousY > latitude) &&
      longitude < (previousX - currentX) * (latitude - currentY) /
      Math.max(0.0000001, previousY - currentY) + currentX;
    if (intersects) inside = !inside;
  }
  return inside;
}

function polygonRings(feature) {
  if (feature.geometry.type === 'Polygon') return feature.geometry.coordinates;
  if (feature.geometry.type === 'MultiPolygon') return feature.geometry.coordinates.flat();
  return [];
}

function constellationFor(longitude, latitude, boundaries, centers) {
  for (const feature of boundaries.features) {
    const rings = polygonRings(feature);
    if (rings.length > 0 && pointInRing(longitude, latitude, rings[0])) {
      return String(feature.id).slice(0, 3);
    }
  }
  // 边界顶点的浮点误差只可能影响边界上的目标，回退到最近星座中心可保证目录不留空。
  let nearest = centers[0];
  let nearestDistance = Number.MAX_VALUE;
  for (const center of centers) {
    const deltaLongitude = adjustLongitude(center.longitude, longitude) - longitude;
    const deltaLatitude = center.latitude - latitude;
    const distance = deltaLongitude * deltaLongitude * Math.cos(latitude * Math.PI / 180) ** 2 +
      deltaLatitude * deltaLatitude;
    if (distance < nearestDistance) {
      nearest = center;
      nearestDistance = distance;
    }
  }
  return nearest.designation;
}

function largestDimensionDegrees(value) {
  const numbers = String(value ?? '').match(/[0-9.]+/g) ?? [];
  if (numbers.length === 0) return 0;
  return Math.max(...numbers.map(Number)) / 60;
}

// 顺序下载可减少 Windows TLS 链路同时握手时的偶发失败。
const constellationsJson = await loadJson('constellations.json');
const linesJson = await loadJson('constellations.lines.json');
const messierJson = await loadJson('messier.json');
const boundariesJson = await loadJson('constellations.bounds.json');

const constellationMap = new Map();
for (const feature of constellationsJson.features) {
  const longitude = Number(feature.geometry.coordinates[0]);
  const latitude = Number(feature.geometry.coordinates[1]);
  const display = feature.properties.display ?? [];
  const designation = String(feature.id);
  const longitudeRadians = longitude * Math.PI / 180;
  const latitudeRadians = latitude * Math.PI / 180;
  const vector = {
    x: Math.cos(latitudeRadians) * Math.cos(longitudeRadians),
    y: Math.cos(latitudeRadians) * Math.sin(longitudeRadians),
    z: Math.sin(latitudeRadians)
  };
  const existing = constellationMap.get(designation);
  if (existing) {
    existing.vectors.push(vector);
    existing.angularSizeDegrees = Math.max(existing.angularSizeDegrees,
      Math.max(10, Math.min(120, Number(display[2] ?? 35))));
    if (designation === 'Ser') existing.nameEn = 'Serpens';
  } else {
    constellationMap.set(designation, {
      designation,
      nameEn: designation === 'Ser' ? 'Serpens' : String(feature.properties.name),
      angularSizeDegrees: Math.max(10, Math.min(120, Number(display[2] ?? 35))),
      vectors: [vector]
    });
  }
}

const constellations = Array.from(constellationMap.values()).map(item => {
  const vector = item.vectors.reduce((sum, current) => ({
    x: sum.x + current.x,
    y: sum.y + current.y,
    z: sum.z + current.z
  }), { x: 0, y: 0, z: 0 });
  const length = Math.sqrt(vector.x ** 2 + vector.y ** 2 + vector.z ** 2);
  const longitude = Math.atan2(vector.y, vector.x) * 180 / Math.PI;
  const latitude = Math.asin(vector.z / length) * 180 / Math.PI;
  return {
    designation: item.designation,
    nameEn: item.nameEn,
    centerRaHours: normalizeLongitude(longitude) / 15,
    centerDecDegrees: latitude,
    angularSizeDegrees: item.angularSizeDegrees
  };
}).sort((first, second) => first.designation.localeCompare(second.designation));

const centerLookup = constellations.map(item => ({
  designation: item.designation,
  longitude: item.centerRaHours * 15 > 180 ? item.centerRaHours * 15 - 360 : item.centerRaHours * 15,
  latitude: item.centerDecDegrees
}));

const messier = messierJson.features.map(feature => {
  const longitude = Number(feature.geometry.coordinates[0]);
  const latitude = Number(feature.geometry.coordinates[1]);
  const number = Number(String(feature.id).replace(/^M/, ''));
  return {
    number,
    designation: `M${number}`,
    alternateName: String(feature.properties.alt ?? ''),
    catalogDesignation: String(feature.properties.desig ?? ''),
    objectType: String(feature.properties.type ?? ''),
    raHours: normalizeLongitude(longitude) / 15,
    decDegrees: latitude,
    magnitude: Number(feature.properties.mag ?? 99),
    angularSizeDegrees: largestDimensionDegrees(feature.properties.dim),
    constellationDesignation: constellationFor(longitude, latitude, boundariesJson, centerLookup)
  };
}).sort((first, second) => first.number - second.number);

const lineMap = new Map();
for (const feature of linesJson.features) {
  const designation = String(feature.id);
  const lines = feature.geometry.coordinates.map(line => line.map(point => ({
    raHours: normalizeLongitude(Number(point[0])) / 15,
    decDegrees: Number(point[1])
  })));
  const existing = lineMap.get(designation);
  if (existing) existing.push(...lines);
  else lineMap.set(designation, lines);
}
const lineGroups = Array.from(lineMap.entries()).map(([designation, lines]) => ({
  designation,
  lines
})).sort((first, second) => first.designation.localeCompare(second.designation));

const generatedSource = `/**
 * 此文件由 tools/import_d3_celestial.mjs 生成，请勿手工修改。
 * 数据来源：d3-celestial ${REVISION}，BSD-3-Clause。
 */

export interface GeneratedConstellationData {
  designation: string;
  nameEn: string;
  centerRaHours: number;
  centerDecDegrees: number;
  angularSizeDegrees: number;
}

export interface GeneratedMessierData {
  number: number;
  designation: string;
  alternateName: string;
  catalogDesignation: string;
  objectType: string;
  raHours: number;
  decDegrees: number;
  magnitude: number;
  angularSizeDegrees: number;
  constellationDesignation: string;
}

export const GENERATED_CONSTELLATIONS: GeneratedConstellationData[] = ${JSON.stringify(constellations, null, 2)};

export const GENERATED_MESSIER: GeneratedMessierData[] = ${JSON.stringify(messier, null, 2)};
`;

const linesOutput = {
  metadata: {
    source: 'd3-celestial',
    revision: REVISION,
    license: 'BSD-3-Clause',
    constellationCount: lineGroups.length
  },
  constellations: lineGroups
};

await mkdir(path.dirname(GENERATED_FILE), { recursive: true });
await mkdir(path.dirname(LINES_FILE), { recursive: true });
await writeFile(GENERATED_FILE, generatedSource, 'utf8');
await writeFile(LINES_FILE, `${JSON.stringify(linesOutput)}\n`, 'utf8');
console.log(`已生成 ${constellations.length} 个星座中心、${messier.length} 个 Messier 目标和 ${lineGroups.length} 组星座线。`);
