/**
 * JPL Horizons 离线冻结样本。
 * 来源：https://ssd.jpl.nasa.gov/api/horizons.api
 * 查询约定：CENTER=500@399、QUANTITIES=1、CSV_FORMAT=YES；站心样本使用
 * CENTER=coord@399、SITE_COORD=113.62,34.75,0.1、QUANTITIES=2。
 * 数值于 2026-07-15 获取，测试运行时不访问网络。
 */
export interface JplGeocentricEquatorialSample {
  label: string;
  objectId: string;
  timestampMs: number;
  raHours: number;
  decDegrees: number;
  toleranceDegrees: number;
}

export interface JplTopocentricEquatorialSample {
  label: string;
  objectId: string;
  timestampMs: number;
  latitudeDegrees: number;
  longitudeDegrees: number;
  elevationMeters: number;
  raHours: number;
  decDegrees: number;
  toleranceDegrees: number;
}

export interface JplIlluminationSample {
  label: string;
  objectId: string;
  timestampMs: number;
  illuminatedPercent: number;
  tolerancePercent: number;
}

export interface JplRiseSetSample {
  label: string;
  objectId: string;
  startAtMs: number;
  latitudeDegrees: number;
  longitudeDegrees: number;
  elevationMeters: number;
  riseAtMs: number;
  setAtMs: number;
  toleranceMinutes: number;
}

export const JPL_GEOCENTRIC_EQUATORIAL_SAMPLES: JplGeocentricEquatorialSample[] = [
  {
    label: '2000-01-01 太阳', objectId: 'solar-sun', timestampMs: Date.UTC(2000, 0, 1, 12, 0, 0),
    raHours: 18.7526000000, decDegrees: -23.0332500000, toleranceDegrees: 0.1
  },
  {
    label: '2000-01-01 火星', objectId: 'planet-mars', timestampMs: Date.UTC(2000, 0, 1, 12, 0, 0),
    raHours: 22.0349722222, decDegrees: -13.1805000000, toleranceDegrees: 0.1
  },
  {
    label: '2024-02-29 火星', objectId: 'planet-mars', timestampMs: Date.UTC(2024, 1, 29, 0, 0, 0),
    raHours: 20.9720472222, decDegrees: -18.2589166667, toleranceDegrees: 0.1
  },
  {
    label: '2024-02-29 月球', objectId: 'solar-moon', timestampMs: Date.UTC(2024, 1, 29, 0, 0, 0),
    raHours: 13.7117472222, decDegrees: -11.8431666667, toleranceDegrees: 0.2
  },
  {
    label: '2026-07-15 火星', objectId: 'planet-mars', timestampMs: Date.UTC(2026, 6, 15, 0, 0, 0),
    raHours: 4.6328555556, decDegrees: 21.9675833333, toleranceDegrees: 0.1
  }
];

export const JPL_TOPOCENTRIC_EQUATORIAL_SAMPLES: JplTopocentricEquatorialSample[] = [
  {
    label: '2024-02-29 郑州站心月球', objectId: 'solar-moon',
    timestampMs: Date.UTC(2024, 1, 29, 0, 0, 0),
    latitudeDegrees: 34.75, longitudeDegrees: 113.62, elevationMeters: 100.0,
    raHours: 13.6865694444, decDegrees: -12.5343611111, toleranceDegrees: 0.2
  }
];

export const JPL_ILLUMINATION_SAMPLES: JplIlluminationSample[] = [
  {
    label: '2024-02-29 月面照明', objectId: 'solar-moon',
    timestampMs: Date.UTC(2024, 1, 29, 0, 0, 0),
    illuminatedPercent: 83.17660, tolerancePercent: 1.0
  }
];

/** APPARENT=REFRACTED、QUANTITIES=4，以目标中心的折射高度 0° 交点线性插值。 */
export const JPL_RISE_SET_SAMPLES: JplRiseSetSample[] = [
  {
    label: '2026-07-15 郑州太阳中心升落', objectId: 'solar-sun',
    startAtMs: Date.UTC(2026, 6, 15, 0, 0, 0),
    latitudeDegrees: 34.75, longitudeDegrees: 113.62, elevationMeters: 100.0,
    setAtMs: Date.UTC(2026, 6, 15, 11, 38, 0),
    riseAtMs: Date.UTC(2026, 6, 15, 21, 25, 20),
    toleranceMinutes: 5.0
  }
];
