import {
  CatalogCoverage,
  CatalogPrecision,
  CelestialObject,
  CelestialType,
  EquatorialCoordinate
} from '../models/DomainModels';
import {
  GENERATED_CONSTELLATIONS,
  GENERATED_MESSIER,
  GeneratedConstellationData,
  GeneratedMessierData
} from './GeneratedSkyCatalog';

function coordinate(raHours: number, decDegrees: number): EquatorialCoordinate {
  return { raHours: raHours, decDegrees: decDegrees, epoch: 2000.0 };
}
function exactObject(id: string, type: CelestialType, nameZh: string, nameEn: string,
  designation: string, constellation: string, raHours: number, decDegrees: number,
  magnitude: number, angularSizeDegrees: number, description: string,
  tags: string[], recommendedFor18mm: boolean): CelestialObject {
  return {
    id: id,
    type: type,
    nameZh: nameZh,
    nameEn: nameEn,
    designation: designation,
    constellation: constellation,
    coordinate: coordinate(raHours, decDegrees),
    magnitude: magnitude,
    angularSizeDegrees: angularSizeDegrees,
    description: description,
    tags: tags,
    precision: CatalogPrecision.EXACT,
    gotoAllowed: true,
    recommendedFor18mm: recommendedFor18mm
  };
}

function indexObject(id: string, type: CelestialType, nameZh: string, nameEn: string,
  designation: string, description: string): CelestialObject {
  return {
    id: id,
    type: type,
    nameZh: nameZh,
    nameEn: nameEn,
    designation: designation,
    constellation: '',
    description: description,
    tags: [designation, nameZh, nameEn],
    precision: CatalogPrecision.INDEX_ONLY,
    gotoAllowed: false,
    recommendedFor18mm: false
  };
}

function dynamicObject(id: string, type: CelestialType, nameZh: string, nameEn: string,
  description: string): CelestialObject {
  return {
    id: id,
    type: type,
    nameZh: nameZh,
    nameEn: nameEn,
    designation: nameEn,
    constellation: '',
    description: description,
    tags: [nameZh, nameEn, '太阳系'],
    precision: CatalogPrecision.DYNAMIC,
    gotoAllowed: true,
    recommendedFor18mm: true
  };
}

/**
 * 比赛现场最常用于校准和演示的亮星。坐标采用 J2000，数据精度足以支持广角 AR 叠加和 GOTO。
 */
const BRIGHT_STARS: CelestialObject[] = [
  exactObject('star-sirius', CelestialType.STAR, '天狼星', 'Sirius', 'Alpha CMa', '大犬座', 6.7525, -16.7161, -1.46, 0.0, '夜空中最亮的恒星。', ['亮星', '冬季', '校准星'], false),
  exactObject('star-canopus', CelestialType.STAR, '老人星', 'Canopus', 'Alpha Car', '船底座', 6.3992, -52.6957, -0.74, 0.0, '全天第二亮恒星，中国南部低纬地区可见。', ['亮星', '南天'], false),
  exactObject('star-arcturus', CelestialType.STAR, '大角星', 'Arcturus', 'Alpha Boo', '牧夫座', 14.2610, 19.1824, -0.05, 0.0, '春季夜空醒目的橙色亮星。', ['亮星', '春季', '校准星'], false),
  exactObject('star-vega', CelestialType.STAR, '织女星', 'Vega', 'Alpha Lyr', '天琴座', 18.6156, 38.7837, 0.03, 0.0, '夏季大三角之一。', ['亮星', '夏季', '校准星'], false),
  exactObject('star-capella', CelestialType.STAR, '五车二', 'Capella', 'Alpha Aur', '御夫座', 5.2782, 45.9980, 0.08, 0.0, '北天明亮恒星。', ['亮星', '冬季', '校准星'], false),
  exactObject('star-rigel', CelestialType.STAR, '参宿七', 'Rigel', 'Beta Ori', '猎户座', 5.2423, -8.2016, 0.13, 0.0, '猎户座的蓝白色亮星。', ['亮星', '冬季'], false),
  exactObject('star-procyon', CelestialType.STAR, '南河三', 'Procyon', 'Alpha CMi', '小犬座', 7.6550, 5.2250, 0.34, 0.0, '冬季大三角之一。', ['亮星', '冬季'], false),
  exactObject('star-betelgeuse', CelestialType.STAR, '参宿四', 'Betelgeuse', 'Alpha Ori', '猎户座', 5.9195, 7.4071, 0.42, 0.0, '猎户座红色超巨星。', ['亮星', '冬季'], false),
  exactObject('star-achernar', CelestialType.STAR, '水委一', 'Achernar', 'Alpha Eri', '波江座', 1.6286, -57.2368, 0.46, 0.0, '南天明亮恒星。', ['亮星', '南天'], false),
  exactObject('star-altair', CelestialType.STAR, '牛郎星', 'Altair', 'Alpha Aql', '天鹰座', 19.8464, 8.8683, 0.77, 0.0, '夏季大三角之一。', ['亮星', '夏季', '校准星'], false),
  exactObject('star-aldebaran', CelestialType.STAR, '毕宿五', 'Aldebaran', 'Alpha Tau', '金牛座', 4.5987, 16.5093, 0.86, 0.0, '金牛座橙色亮星。', ['亮星', '冬季'], false),
  exactObject('star-antares', CelestialType.STAR, '心宿二', 'Antares', 'Alpha Sco', '天蝎座', 16.4901, -26.4320, 0.96, 0.0, '天蝎座红色超巨星。', ['亮星', '夏季'], false),
  exactObject('star-spica', CelestialType.STAR, '角宿一', 'Spica', 'Alpha Vir', '室女座', 13.4199, -11.1613, 0.97, 0.0, '室女座最亮星。', ['亮星', '春季'], false),
  exactObject('star-pollux', CelestialType.STAR, '北河三', 'Pollux', 'Beta Gem', '双子座', 7.7553, 28.0262, 1.14, 0.0, '双子座较亮的一颗星。', ['亮星', '冬季'], false),
  exactObject('star-fomalhaut', CelestialType.STAR, '北落师门', 'Fomalhaut', 'Alpha PsA', '南鱼座', 22.9608, -29.6222, 1.16, 0.0, '秋季南方天空的孤独亮星。', ['亮星', '秋季'], false),
  exactObject('star-deneb', CelestialType.STAR, '天津四', 'Deneb', 'Alpha Cyg', '天鹅座', 20.6905, 45.2803, 1.25, 0.0, '夏季大三角之一。', ['亮星', '夏季', '校准星'], false),
  exactObject('star-regulus', CelestialType.STAR, '轩辕十四', 'Regulus', 'Alpha Leo', '狮子座', 10.1395, 11.9672, 1.35, 0.0, '狮子座最亮星。', ['亮星', '春季'], false),
  exactObject('star-castor', CelestialType.STAR, '北河二', 'Castor', 'Alpha Gem', '双子座', 7.5767, 31.8883, 1.58, 0.0, '双子座著名多星系统。', ['亮星', '冬季'], false),
  exactObject('star-bellatrix', CelestialType.STAR, '参宿五', 'Bellatrix', 'Gamma Ori', '猎户座', 5.4189, 6.3497, 1.64, 0.0, '猎户座肩部亮星。', ['亮星', '冬季'], false),
  exactObject('star-alnilam', CelestialType.STAR, '参宿二', 'Alnilam', 'Epsilon Ori', '猎户座', 5.6036, -1.2019, 1.69, 0.0, '猎户腰带中央恒星。', ['亮星', '冬季'], false),
  exactObject('star-alphard', CelestialType.STAR, '星宿一', 'Alphard', 'Alpha Hya', '长蛇座', 9.4598, -8.6586, 1.98, 0.0, '长蛇座最亮星。', ['亮星', '春季'], false),
  exactObject('star-polaris', CelestialType.STAR, '北极星', 'Polaris', 'Alpha UMi', '小熊座', 2.5303, 89.2641, 1.98, 0.0, '接近北天极，是极轴校准和方位辨识的重要目标。', ['亮星', '北天', '校准星'], false),
  exactObject('star-alpheratz', CelestialType.STAR, '壁宿二', 'Alpheratz', 'Alpha And', '仙女座', 0.1398, 29.0904, 2.06, 0.0, '仙女座与飞马座大四边形的连接星。', ['亮星', '秋季'], false),
  exactObject('star-mirach', CelestialType.STAR, '奎宿九', 'Mirach', 'Beta And', '仙女座', 1.1622, 35.6206, 2.05, 0.0, '寻找 M31 的常用跳星锚点。', ['亮星', '秋季', '寻星'], false),
  exactObject('star-almach', CelestialType.STAR, '天大将军一', 'Almach', 'Gamma And', '仙女座', 2.0649, 42.3297, 2.10, 0.0, '仙女座东端的彩色双星。', ['亮星', '秋季'], false),
  exactObject('star-kochab', CelestialType.STAR, '帝', 'Kochab', 'Beta UMi', '小熊座', 14.8451, 74.1555, 2.08, 0.0, '小熊座亮星，可辅助寻找北极星。', ['亮星', '北天'], false)
];

/** 完整 88 星座索引；带精确中心的重点星座会覆盖对应索引项并参与 AR 投影。 */
const CONSTELLATION_NAMES: string[] = [
  'Andromeda|仙女座', 'Antlia|唧筒座', 'Apus|天燕座', 'Aquarius|宝瓶座', 'Aquila|天鹰座',
  'Ara|天坛座', 'Aries|白羊座', 'Auriga|御夫座', 'Bootes|牧夫座', 'Caelum|雕具座',
  'Camelopardalis|鹿豹座', 'Cancer|巨蟹座', 'Canes Venatici|猎犬座', 'Canis Major|大犬座',
  'Canis Minor|小犬座', 'Capricornus|摩羯座', 'Carina|船底座', 'Cassiopeia|仙后座',
  'Centaurus|半人马座', 'Cepheus|仙王座', 'Cetus|鲸鱼座', 'Chamaeleon|蝘蜓座',
  'Circinus|圆规座', 'Columba|天鸽座', 'Coma Berenices|后发座', 'Corona Australis|南冕座',
  'Corona Borealis|北冕座', 'Corvus|乌鸦座', 'Crater|巨爵座', 'Crux|南十字座',
  'Cygnus|天鹅座', 'Delphinus|海豚座', 'Dorado|剑鱼座', 'Draco|天龙座', 'Equuleus|小马座',
  'Eridanus|波江座', 'Fornax|天炉座', 'Gemini|双子座', 'Grus|天鹤座', 'Hercules|武仙座',
  'Horologium|时钟座', 'Hydra|长蛇座', 'Hydrus|水蛇座', 'Indus|印第安座', 'Lacerta|蝎虎座',
  'Leo|狮子座', 'Leo Minor|小狮座', 'Lepus|天兔座', 'Libra|天秤座', 'Lupus|豺狼座',
  'Lynx|天猫座', 'Lyra|天琴座', 'Mensa|山案座', 'Microscopium|显微镜座', 'Monoceros|麒麟座',
  'Musca|苍蝇座', 'Norma|矩尺座', 'Octans|南极座', 'Ophiuchus|蛇夫座', 'Orion|猎户座',
  'Pavo|孔雀座', 'Pegasus|飞马座', 'Perseus|英仙座', 'Phoenix|凤凰座', 'Pictor|绘架座',
  'Pisces|双鱼座', 'Piscis Austrinus|南鱼座', 'Puppis|船尾座', 'Pyxis|罗盘座', 'Reticulum|网罟座',
  'Sagitta|天箭座', 'Sagittarius|人马座', 'Scorpius|天蝎座', 'Sculptor|玉夫座', 'Scutum|盾牌座',
  'Serpens|巨蛇座', 'Sextans|六分仪座', 'Taurus|金牛座', 'Telescopium|望远镜座',
  'Triangulum|三角座', 'Triangulum Australe|南三角座', 'Tucana|杜鹃座', 'Ursa Major|大熊座',
  'Ursa Minor|小熊座', 'Vela|船帆座', 'Virgo|室女座', 'Volans|飞鱼座', 'Vulpecula|狐狸座'
];

const EXACT_CONSTELLATIONS: CelestialObject[] = [
  exactObject('constellation-andromeda', CelestialType.CONSTELLATION, '仙女座', 'Andromeda', 'And', '仙女座', 0.807, 37.43, 0.0, 25.0, '秋季北天代表星座，包含 M31。', ['星座', '秋季'], true),
  exactObject('constellation-aquila', CelestialType.CONSTELLATION, '天鹰座', 'Aquila', 'Aql', '天鹰座', 19.67, 3.41, 0.0, 20.0, '以牛郎星为标志的夏季星座。', ['星座', '夏季'], true),
  exactObject('constellation-auriga', CelestialType.CONSTELLATION, '御夫座', 'Auriga', 'Aur', '御夫座', 6.07, 42.0, 0.0, 24.0, '冬季北天的大型星座。', ['星座', '冬季'], true),
  exactObject('constellation-bootes', CelestialType.CONSTELLATION, '牧夫座', 'Bootes', 'Boo', '牧夫座', 14.71, 31.2, 0.0, 25.0, '由大角星领衔的春季星座。', ['星座', '春季'], true),
  exactObject('constellation-cassiopeia', CelestialType.CONSTELLATION, '仙后座', 'Cassiopeia', 'Cas', '仙后座', 1.0, 60.0, 0.0, 25.0, '北天醒目的 W 形星座。', ['星座', '北天'], true),
  exactObject('constellation-cygnus', CelestialType.CONSTELLATION, '天鹅座', 'Cygnus', 'Cyg', '天鹅座', 20.62, 42.0, 0.0, 30.0, '沿银河展开的北十字。', ['星座', '夏季', '银河'], true),
  exactObject('constellation-gemini', CelestialType.CONSTELLATION, '双子座', 'Gemini', 'Gem', '双子座', 7.07, 22.6, 0.0, 28.0, '以北河二、北河三为标志的冬季星座。', ['星座', '冬季'], true),
  exactObject('constellation-hercules', CelestialType.CONSTELLATION, '武仙座', 'Hercules', 'Her', '武仙座', 17.39, 27.5, 0.0, 35.0, '包含球状星团 M13。', ['星座', '夏季'], true),
  exactObject('constellation-leo', CelestialType.CONSTELLATION, '狮子座', 'Leo', 'Leo', '狮子座', 10.67, 13.1, 0.0, 30.0, '春季黄道星座。', ['星座', '春季'], true),
  exactObject('constellation-lyra', CelestialType.CONSTELLATION, '天琴座', 'Lyra', 'Lyr', '天琴座', 18.85, 36.7, 0.0, 12.0, '以织女星为标志的小型星座。', ['星座', '夏季'], true),
  exactObject('constellation-orion', CelestialType.CONSTELLATION, '猎户座', 'Orion', 'Ori', '猎户座', 5.58, 1.0, 0.0, 30.0, '冬季最易辨认的星座，包含 M42。', ['星座', '冬季'], true),
  exactObject('constellation-pegasus', CelestialType.CONSTELLATION, '飞马座', 'Pegasus', 'Peg', '飞马座', 22.70, 19.5, 0.0, 35.0, '秋季星空中的大四边形。', ['星座', '秋季'], true),
  exactObject('constellation-sagittarius', CelestialType.CONSTELLATION, '人马座', 'Sagittarius', 'Sgr', '人马座', 19.0, -25.0, 0.0, 30.0, '银河中心方向，包含多个明亮星云。', ['星座', '夏季', '银河'], true),
  exactObject('constellation-scorpius', CelestialType.CONSTELLATION, '天蝎座', 'Scorpius', 'Sco', '天蝎座', 16.89, -30.7, 0.0, 30.0, '以心宿二为标志的夏季星座。', ['星座', '夏季'], true),
  exactObject('constellation-taurus', CelestialType.CONSTELLATION, '金牛座', 'Taurus', 'Tau', '金牛座', 4.70, 17.0, 0.0, 35.0, '包含昴星团和毕星团。', ['星座', '冬季'], true),
  exactObject('constellation-ursa-major', CelestialType.CONSTELLATION, '大熊座', 'Ursa Major', 'UMa', '大熊座', 11.31, 50.7, 0.0, 45.0, '包含北斗七星的北天大星座。', ['星座', '北天'], true),
  exactObject('constellation-ursa-minor', CelestialType.CONSTELLATION, '小熊座', 'Ursa Minor', 'UMi', '小熊座', 15.0, 78.0, 0.0, 28.0, '包含北极星。', ['星座', '北天'], true),
  exactObject('constellation-virgo', CelestialType.CONSTELLATION, '室女座', 'Virgo', 'Vir', '室女座', 13.41, -4.2, 0.0, 40.0, '春季大型黄道星座。', ['星座', '春季'], true)
];

const EXACT_MESSIER: CelestialObject[] = [
  exactObject('messier-1', CelestialType.MESSIER, '蟹状星云', 'Crab Nebula', 'M1', '金牛座', 5.5756, 22.0145, 8.4, 0.12, '超新星遗迹，18mm 下仅呈小亮斑。', ['Messier', '超新星遗迹'], false),
  exactObject('messier-8', CelestialType.MESSIER, '礁湖星云', 'Lagoon Nebula', 'M8', '人马座', 18.0600, -24.3867, 6.0, 1.50, '银河中心附近的大型发射星云，适合广角环境星野。', ['Messier', '星云', '银河'], true),
  exactObject('messier-13', CelestialType.MESSIER, '武仙座球状星团', 'Hercules Cluster', 'M13', '武仙座', 16.6949, 36.4613, 5.8, 0.33, '北天著名球状星团，18mm 下目标较小。', ['Messier', '球状星团'], false),
  exactObject('messier-16', CelestialType.MESSIER, '鹰状星云', 'Eagle Nebula', 'M16', '巨蛇座', 18.3134, -13.8067, 6.0, 0.58, '包含“创生之柱”的恒星形成区。', ['Messier', '星云'], false),
  exactObject('messier-20', CelestialType.MESSIER, '三裂星云', 'Trifid Nebula', 'M20', '人马座', 18.0331, -23.0292, 6.3, 0.47, '红蓝相间的恒星形成区，可与 M8 同框。', ['Messier', '星云', '银河'], true),
  exactObject('messier-24', CelestialType.MESSIER, '人马座恒星云', 'Sagittarius Star Cloud', 'M24', '人马座', 18.2820, -18.5500, 4.6, 1.50, '银河中高密度星野，适合 18mm 广角。', ['Messier', '星云', '银河'], true),
  exactObject('messier-31', CelestialType.MESSIER, '仙女座星系', 'Andromeda Galaxy', 'M31', '仙女座', 0.7123, 41.2692, 3.44, 3.17, '距离银河系最近的大型旋涡星系，适合广角环境星野。', ['Messier', '星系', '秋季'], true),
  exactObject('messier-33', CelestialType.MESSIER, '三角座星系', 'Triangulum Galaxy', 'M33', '三角座', 1.5641, 30.6602, 5.72, 1.18, '低表面亮度旋涡星系，城市环境拍摄难度较高。', ['Messier', '星系'], false),
  exactObject('messier-42', CelestialType.MESSIER, '猎户座大星云', 'Orion Nebula', 'M42', '猎户座', 5.5881, -5.3911, 4.0, 1.08, '明亮的大型发射星云，冬季比赛演示目标。', ['Messier', '星云', '冬季'], true),
  exactObject('messier-44', CelestialType.MESSIER, '蜂巢星团', 'Beehive Cluster', 'M44', '巨蟹座', 8.6728, 19.6721, 3.1, 1.58, '大型疏散星团，适合 18mm 广角构图。', ['Messier', '疏散星团'], true),
  exactObject('messier-45', CelestialType.MESSIER, '昴星团', 'Pleiades', 'M45', '金牛座', 3.7903, 24.1167, 1.6, 1.83, '肉眼可见的大型疏散星团，适合广角拍摄。', ['Messier', '疏散星团', '冬季'], true),
  exactObject('messier-57', CelestialType.MESSIER, '环状星云', 'Ring Nebula', 'M57', '天琴座', 18.8931, 33.0292, 8.8, 0.024, '著名行星状星云，18mm 无法呈现环状细节。', ['Messier', '行星状星云'], false),
  exactObject('messier-81', CelestialType.MESSIER, '波德星系', 'Bode Galaxy', 'M81', '大熊座', 9.9259, 69.0653, 6.9, 0.45, '与 M82 邻近的大型旋涡星系。', ['Messier', '星系'], false),
  exactObject('messier-82', CelestialType.MESSIER, '雪茄星系', 'Cigar Galaxy', 'M82', '大熊座', 9.9313, 69.6797, 8.4, 0.18, '活跃的星暴星系，可与 M81 同框。', ['Messier', '星系'], false),
  exactObject('messier-101', CelestialType.MESSIER, '风车星系', 'Pinwheel Galaxy', 'M101', '大熊座', 14.0535, 54.3488, 7.9, 0.48, '低表面亮度正面旋涡星系。', ['Messier', '星系'], false),
  exactObject('messier-104', CelestialType.MESSIER, '草帽星系', 'Sombrero Galaxy', 'M104', '室女座', 12.6665, -11.6231, 8.0, 0.15, '具有明显尘埃带的旋涡星系。', ['Messier', '星系'], false)
];

const SOLAR_SYSTEM: CelestialObject[] = [
  dynamicObject('solar-sun', CelestialType.SUN, '太阳', 'Sun', '仅可在专用太阳滤镜和安全模式下观测，软件默认禁止普通夜间 GOTO。'),
  dynamicObject('solar-moon', CelestialType.MOON, '月球', 'Moon', '地球唯一的天然卫星，广角延时和地景构图的重要目标。'),
  dynamicObject('planet-mercury', CelestialType.PLANET, '水星', 'Mercury', '最靠近太阳的行星。'),
  dynamicObject('planet-venus', CelestialType.PLANET, '金星', 'Venus', '夜空中最亮的行星。'),
  dynamicObject('planet-mars', CelestialType.PLANET, '火星', 'Mars', '具有红色外观的类地行星。'),
  dynamicObject('planet-jupiter', CelestialType.PLANET, '木星', 'Jupiter', '太阳系最大的行星。'),
  dynamicObject('planet-saturn', CelestialType.PLANET, '土星', 'Saturn', '拥有显著行星环。'),
  dynamicObject('planet-uranus', CelestialType.PLANET, '天王星', 'Uranus', '远日气态冰巨星。'),
  dynamicObject('planet-neptune', CelestialType.PLANET, '海王星', 'Neptune', '太阳系最外侧的主要行星。')
];

function slugify(nameEn: string): string {
  return nameEn.toLowerCase().replace(/ /g, '-');
}

function findExactConstellation(nameEn: string): CelestialObject | undefined {
  for (let index: number = 0; index < EXACT_CONSTELLATIONS.length; index++) {
    if (EXACT_CONSTELLATIONS[index].nameEn === nameEn) {
      return EXACT_CONSTELLATIONS[index];
    }
  }
  return undefined;
}

function findGeneratedConstellation(nameEn: string): GeneratedConstellationData | undefined {
  for (let index: number = 0; index < GENERATED_CONSTELLATIONS.length; index++) {
    if (GENERATED_CONSTELLATIONS[index].nameEn === nameEn) {
      return GENERATED_CONSTELLATIONS[index];
    }
  }
  return undefined;
}

function findExactMessier(number: number): CelestialObject | undefined {
  const id: string = `messier-${number}`;
  for (let index: number = 0; index < EXACT_MESSIER.length; index++) {
    if (EXACT_MESSIER[index].id === id) {
      return EXACT_MESSIER[index];
    }
  }
  return undefined;
}

function findGeneratedMessier(number: number): GeneratedMessierData | undefined {
  for (let index: number = 0; index < GENERATED_MESSIER.length; index++) {
    if (GENERATED_MESSIER[index].number === number) {
      return GENERATED_MESSIER[index];
    }
  }
  return undefined;
}

function buildConstellations(): CelestialObject[] {
  const result: CelestialObject[] = [];
  for (let index: number = 0; index < CONSTELLATION_NAMES.length; index++) {
    const parts: string[] = CONSTELLATION_NAMES[index].split('|');
    const exact: CelestialObject | undefined = findExactConstellation(parts[0]);
    const generated: GeneratedConstellationData | undefined = findGeneratedConstellation(parts[0]);
    if (generated === undefined) {
      // 固定版本数据若缺项应明确降级，不能伪造星座中心。
      result.push(indexObject(`constellation-${slugify(parts[0])}`, CelestialType.CONSTELLATION,
        parts[1], parts[0], parts[0], 'IAU 星座索引；当前离线数据缺少可靠中心坐标。'));
      continue;
    }
    result.push(exactObject(`constellation-${slugify(parts[0])}`, CelestialType.CONSTELLATION,
      parts[1], parts[0], generated.designation, parts[1],
      generated.centerRaHours, generated.centerDecDegrees, 0.0,
      exact === undefined || exact.angularSizeDegrees === undefined ?
        generated.angularSizeDegrees : exact.angularSizeDegrees,
      exact === undefined ? `IAU 88 星座之一；离线星图包含其中心和主要连线。` : exact.description,
      exact === undefined ? ['星座', parts[1], parts[0]] : exact.tags,
      exact === undefined ? generated.angularSizeDegrees >= 20.0 : exact.recommendedFor18mm));
  }
  return result;
}

function constellationNameByDesignation(designation: string, constellations: CelestialObject[]): string {
  for (let index: number = 0; index < constellations.length; index++) {
    if (constellations[index].designation === designation) {
      return constellations[index].nameZh;
    }
  }
  return '';
}

function messierTypeName(type: string): string {
  if (type === 'g' || type === 's' || type === 's0' || type === 'sd' || type === 'i' || type === 'e') {
    return '星系';
  }
  if (type === 'oc') return '疏散星团';
  if (type === 'gc') return '球状星团';
  if (type === 'pn') return '行星状星云';
  if (type === 'snr') return '超新星遗迹';
  if (type === 'dn') return '暗星云';
  if (type === 'rn') return '反射星云';
  if (type === 'bn' || type === 'en' || type === 'sfr') return '星云';
  return '深空天体';
}

function buildMessier(constellations: CelestialObject[]): CelestialObject[] {
  const result: CelestialObject[] = [];
  for (let number: number = 1; number <= 110; number++) {
    const exact: CelestialObject | undefined = findExactMessier(number);
    const generated: GeneratedMessierData | undefined = findGeneratedMessier(number);
    if (generated === undefined) {
      result.push(indexObject(`messier-${number}`, CelestialType.MESSIER, `梅西耶 ${number}`,
        `Messier ${number}`, `M${number}`, '离线数据缺少可靠坐标，当前仅允许检索。'));
      continue;
    }
    const typeName: string = messierTypeName(generated.objectType);
    const constellation: string = constellationNameByDesignation(
      generated.constellationDesignation, constellations);
    const alternateName: string = generated.alternateName.length > 0 ?
      generated.alternateName : `Messier ${number}`;
    result.push(exactObject(`messier-${number}`, CelestialType.MESSIER,
      exact === undefined ? `梅西耶 ${number}` : exact.nameZh,
      exact === undefined ? alternateName : exact.nameEn,
      generated.designation, constellation,
      generated.raHours, generated.decDegrees, generated.magnitude, generated.angularSizeDegrees,
      exact === undefined ? `${generated.designation} 是位于${constellation}的${typeName}，可离线查看和规划。` : exact.description,
      exact === undefined ? ['Messier', typeName, generated.catalogDesignation] : exact.tags,
      exact === undefined ? generated.angularSizeDegrees >= 0.75 && generated.magnitude <= 7.0 :
        exact.recommendedFor18mm));
  }
  return result;
}

const CONSTELLATIONS: CelestialObject[] = buildConstellations();
const MESSIER_OBJECTS: CelestialObject[] = buildMessier(CONSTELLATIONS);
const ALL_OBJECTS: CelestialObject[] = BRIGHT_STARS.concat(CONSTELLATIONS, MESSIER_OBJECTS, SOLAR_SYSTEM);

export class CelestialCatalog {
  static all(): CelestialObject[] {
    return ALL_OBJECTS.slice();
  }

  static brightStars(): CelestialObject[] {
    return BRIGHT_STARS.slice();
  }

  static constellations(): CelestialObject[] {
    return CONSTELLATIONS.slice();
  }

  static messierObjects(): CelestialObject[] {
    return MESSIER_OBJECTS.slice();
  }

  static solarSystem(): CelestialObject[] {
    return SOLAR_SYSTEM.slice();
  }

  static getById(id: string): CelestialObject | undefined {
    for (let index: number = 0; index < ALL_OBJECTS.length; index++) {
      if (ALL_OBJECTS[index].id === id) {
        return ALL_OBJECTS[index];
      }
    }
    return undefined;
  }

  static search(keyword: string, limit: number = 30): CelestialObject[] {
    const normalized: string = keyword.trim().toLowerCase();
    if (normalized.length === 0) {
      return ALL_OBJECTS.slice(0, limit);
    }
    const matches: CelestialObject[] = [];
    for (let index: number = 0; index < ALL_OBJECTS.length && matches.length < limit; index++) {
      const item: CelestialObject = ALL_OBJECTS[index];
      const searchable: string = `${item.nameZh} ${item.nameEn} ${item.designation} ${item.constellation}`.toLowerCase();
      if (searchable.includes(normalized)) {
        matches.push(item);
      }
    }
    return matches;
  }

  static exactProjectable(): CelestialObject[] {
    const result: CelestialObject[] = [];
    for (let index: number = 0; index < ALL_OBJECTS.length; index++) {
      if (ALL_OBJECTS[index].precision === CatalogPrecision.EXACT) {
        result.push(ALL_OBJECTS[index]);
      }
    }
    return result;
  }

  static recommendedFor18mm(): CelestialObject[] {
    const result: CelestialObject[] = [];
    for (let index: number = 0; index < ALL_OBJECTS.length; index++) {
      if (ALL_OBJECTS[index].recommendedFor18mm) {
        result.push(ALL_OBJECTS[index]);
      }
    }
    return result;
  }

  static coverage(): CatalogCoverage {
    return {
      exactBrightStars: BRIGHT_STARS.length,
      constellationIndexCount: CONSTELLATIONS.length,
      exactConstellationAnchors: CONSTELLATIONS.length,
      messierIndexCount: MESSIER_OBJECTS.length,
      exactMessierTargets: MESSIER_OBJECTS.length,
      dynamicSolarSystemCount: SOLAR_SYSTEM.length,
      strategy: '完整离线覆盖 IAU 88 星座中心与连线、M1-M110 精确坐标、肉眼恒星和动态太阳系目标。'
    };
  }
}
