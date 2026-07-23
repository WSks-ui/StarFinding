# Third-party data and software

## HYG Database v4.1

The offline visible-star catalog in `entry/src/main/resources/rawfile/visible_stars.json` is derived from the [HYG Database](https://github.com/astronexus/HYG-Database) by David Nash.

The HYG Database is licensed under the [Creative Commons Attribution-ShareAlike 4.0 International License](https://creativecommons.org/licenses/by-sa/4.0/). The generated catalog keeps only stars with apparent magnitude no greater than 6.5 and records the source, version, filter and license in the JSON metadata.

Any redistributed modified version of this derived catalog must remain available under CC BY-SA 4.0.

## d3-celestial constellation and Messier data

The offline constellation centers, constellation line geometry and Messier catalog are derived from
[d3-celestial](https://github.com/ofrohn/d3-celestial) by Olaf Frohn, pinned to revision
`7e720a3de062059d4c5400a379146a601d9010e0`.

d3-celestial is licensed under the BSD 3-Clause License. The reproducible importer is stored at
`tools/import_d3_celestial.mjs`; it generates `GeneratedSkyCatalog.ets` and `normal_sky_lines.json`
without adding a runtime network dependency.

## Astronomy Engine 2.1.19

The offline ephemeris implementation in `entry/src/main/ets/vendor/astronomy-engine/astronomy.js`
is vendored from [Astronomy Engine](https://github.com/cosinekitty/astronomy), version `2.1.19`,
by Don Cross. The vendored ESM file has SHA-256
`068F1445ED0C636C94818FE6D20D7D125120E605E0BAB9FC4675C3D531BE5AD7`.

Astronomy Engine is licensed under the MIT License. The application uses it entirely offline through
a narrow numeric JavaScript bridge; no ephemeris data or executable code is downloaded at runtime.
The complete license text is retained beside the vendored source as `LICENSE.txt`.

## ESO/S. Brunier visible-light all-sky image

The optional photography backdrop in
`entry/src/main/resources/rawfile/sky_survey_eso_visible_6000x3000.png` is derived from
[The Milky Way Panorama](https://www.eso.org/public/images/eso0932a/) by ESO/S. Brunier.
The source image is used under the Creative Commons Attribution 4.0 International License
(CC BY 4.0).

- Official 6000×3000 source SHA-256:
  `60400C92C54B7C1BD12299C69E83B16E5B6256E7DABACC478C021758ECD28179`.
- Packaged 6000×3000 lossless PNG resource SHA-256:
  `4BFCCC9F6C1619B58A6949D0AEDBA146D8E00A4E0A519861B989320B3CF3925A`.

The reproducible build tool is `tools/build_sky_survey_backdrop.py`. It verifies the source hash,
preserves the complete 6000×3000 image without destructive resizing or blur, and only applies a
narrow periodic blend at the left/right all-sky seam before writing a lossless offline PNG.
Photography mode hides the duplicate HYG point layer while dynamic solar-system objects continue to
come from the application ephemeris. The application never downloads imagery at runtime. This
backdrop is a visual reference only; coordinate calculations, observation planning,
plate solving and device control continue to use their own astronomical data sources.
