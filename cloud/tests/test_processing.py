from __future__ import annotations

import numpy as np

from app.image_processing import decode_image, process_local


def test_local_enhancement_preserves_detected_star_cores(synthetic_sky_bytes: bytes) -> None:
    original, _ = decode_image(synthetic_sky_bytes)
    result, mask, stats = process_local(original, strength=0.8)

    original_array = np.asarray(original, dtype=np.int16)
    result_array = np.asarray(result, dtype=np.int16)
    mask_array = np.asarray(mask, dtype=np.float32) / 255.0
    protected = mask_array >= 0.99

    assert result.size == original.size
    assert protected.any()
    assert np.max(np.abs(original_array[protected] - result_array[protected])) <= 1
    assert 0.0 < stats.protected_pixel_ratio < 0.2
    assert stats.algorithm_version == "star-protect-local-v1"


def test_local_enhancement_changes_background(synthetic_sky_bytes: bytes) -> None:
    original, _ = decode_image(synthetic_sky_bytes)
    result, mask, _ = process_local(original, strength=0.8)
    mask_array = np.asarray(mask, dtype=np.float32) / 255.0
    difference = np.abs(
        np.asarray(original, dtype=np.int16) - np.asarray(result, dtype=np.int16)
    )

    assert float(difference[mask_array < 0.05].mean()) > 0.5
