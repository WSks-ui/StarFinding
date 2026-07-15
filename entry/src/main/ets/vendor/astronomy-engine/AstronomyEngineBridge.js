import {
  Body,
  Equator,
  EquatorFromVector,
  GeoVector,
  Horizon,
  Illumination,
  MakeTime,
  MoonPhase,
  Observer,
  RotateVector,
  Rotation_EQD_EQJ,
  Rotation_EQJ_EQD,
  Rotation_HOR_EQJ,
  Spherical,
  Vector,
  VectorFromHorizon
} from './astronomy.js';

function resolveBody(bodyId) {
  if (bodyId === 'solar-sun') return Body.Sun;
  if (bodyId === 'solar-moon') return Body.Moon;
  if (bodyId === 'planet-mercury') return Body.Mercury;
  if (bodyId === 'planet-venus') return Body.Venus;
  if (bodyId === 'planet-mars') return Body.Mars;
  if (bodyId === 'planet-jupiter') return Body.Jupiter;
  if (bodyId === 'planet-saturn') return Body.Saturn;
  if (bodyId === 'planet-uranus') return Body.Uranus;
  if (bodyId === 'planet-neptune') return Body.Neptune;
  throw new Error(`Unsupported solar-system body: ${bodyId}`);
}

function dateFromMilliseconds(timestampMs) {
  if (!Number.isFinite(timestampMs)) {
    throw new Error('Observation timestamp must be finite');
  }
  return new Date(timestampMs);
}

function observerFromNumbers(latitudeDegrees, longitudeDegrees, elevationMeters) {
  return new Observer(latitudeDegrees, longitudeDegrees, elevationMeters);
}

function vectorFromEquatorial(raHours, decDegrees, timestampMs) {
  const raRadians = raHours * Math.PI / 12.0;
  const decRadians = decDegrees * Math.PI / 180.0;
  const cosine = Math.cos(decRadians);
  return new Vector(
    cosine * Math.cos(raRadians),
    cosine * Math.sin(raRadians),
    Math.sin(decRadians),
    MakeTime(dateFromMilliseconds(timestampMs))
  );
}

export function geocentricEqj(bodyId, timestampMs) {
  const vector = GeoVector(resolveBody(bodyId), dateFromMilliseconds(timestampMs), true);
  const equatorial = EquatorFromVector(vector);
  return [equatorial.ra, equatorial.dec, equatorial.dist];
}

export function topocentricEqd(bodyId, timestampMs, latitudeDegrees, longitudeDegrees, elevationMeters) {
  const equatorial = Equator(
    resolveBody(bodyId),
    dateFromMilliseconds(timestampMs),
    observerFromNumbers(latitudeDegrees, longitudeDegrees, elevationMeters),
    true,
    true
  );
  return [equatorial.ra, equatorial.dec, equatorial.dist];
}

export function horizontalBody(bodyId, timestampMs, latitudeDegrees, longitudeDegrees,
  elevationMeters, applyRefraction) {
  const date = dateFromMilliseconds(timestampMs);
  const observer = observerFromNumbers(latitudeDegrees, longitudeDegrees, elevationMeters);
  const equatorial = Equator(resolveBody(bodyId), date, observer, true, true);
  const horizontal = Horizon(date, observer, equatorial.ra, equatorial.dec,
    applyRefraction ? 'normal' : null);
  return [horizontal.azimuth, horizontal.altitude];
}

export function eqjToEqd(raHours, decDegrees, timestampMs) {
  const source = vectorFromEquatorial(raHours, decDegrees, timestampMs);
  const rotated = RotateVector(Rotation_EQJ_EQD(dateFromMilliseconds(timestampMs)), source);
  const equatorial = EquatorFromVector(rotated);
  return [equatorial.ra, equatorial.dec];
}

export function eqdToEqj(raHours, decDegrees, timestampMs) {
  const source = vectorFromEquatorial(raHours, decDegrees, timestampMs);
  const rotated = RotateVector(Rotation_EQD_EQJ(dateFromMilliseconds(timestampMs)), source);
  const equatorial = EquatorFromVector(rotated);
  return [equatorial.ra, equatorial.dec];
}

export function horizontalFromEqj(raHours, decDegrees, timestampMs, latitudeDegrees,
  longitudeDegrees, elevationMeters, applyRefraction) {
  const date = dateFromMilliseconds(timestampMs);
  const observer = observerFromNumbers(latitudeDegrees, longitudeDegrees, elevationMeters);
  const eqd = eqjToEqd(raHours, decDegrees, timestampMs);
  const horizontal = Horizon(date, observer, eqd[0], eqd[1], applyRefraction ? 'normal' : null);
  return [horizontal.azimuth, horizontal.altitude];
}

export function eqjFromHorizontal(azimuthDegrees, altitudeDegrees, timestampMs, latitudeDegrees,
  longitudeDegrees, elevationMeters, includesRefraction) {
  const date = dateFromMilliseconds(timestampMs);
  const observer = observerFromNumbers(latitudeDegrees, longitudeDegrees, elevationMeters);
  const horizontal = new Spherical(altitudeDegrees, azimuthDegrees, 1.0);
  const horizontalVector = VectorFromHorizon(horizontal, date, includesRefraction ? 'normal' : null);
  const eqjVector = RotateVector(Rotation_HOR_EQJ(date, observer), horizontalVector);
  const equatorial = EquatorFromVector(eqjVector);
  return [equatorial.ra, equatorial.dec];
}

export function bodyIllumination(bodyId, timestampMs) {
  const illumination = Illumination(resolveBody(bodyId), dateFromMilliseconds(timestampMs));
  const ringTilt = illumination.ring_tilt === undefined ? Number.NaN : illumination.ring_tilt;
  return [
    illumination.mag,
    illumination.phase_fraction,
    illumination.phase_angle,
    illumination.geo_dist,
    ringTilt
  ];
}

export function moonPhaseDegrees(timestampMs) {
  return MoonPhase(dateFromMilliseconds(timestampMs));
}
