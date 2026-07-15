export function geocentricEqj(bodyId: string, timestampMs: number): number[];

export function topocentricEqd(bodyId: string, timestampMs: number, latitudeDegrees: number,
  longitudeDegrees: number, elevationMeters: number): number[];

export function horizontalBody(bodyId: string, timestampMs: number, latitudeDegrees: number,
  longitudeDegrees: number, elevationMeters: number, applyRefraction: boolean): number[];

export function eqjToEqd(raHours: number, decDegrees: number, timestampMs: number): number[];

export function eqdToEqj(raHours: number, decDegrees: number, timestampMs: number): number[];

export function horizontalFromEqj(raHours: number, decDegrees: number, timestampMs: number,
  latitudeDegrees: number, longitudeDegrees: number, elevationMeters: number,
  applyRefraction: boolean): number[];

export function eqjFromHorizontal(azimuthDegrees: number, altitudeDegrees: number,
  timestampMs: number, latitudeDegrees: number, longitudeDegrees: number,
  elevationMeters: number, includesRefraction: boolean): number[];

export function bodyIllumination(bodyId: string, timestampMs: number): number[];

export function moonPhaseDegrees(timestampMs: number): number;
