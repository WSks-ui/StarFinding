from __future__ import annotations

from io import BytesIO

import numpy as np
import pytest
from PIL import Image


@pytest.fixture
def synthetic_sky_bytes() -> bytes:
    rng = np.random.default_rng(20260711)
    image = rng.normal(24, 3, size=(96, 144, 3)).clip(0, 255).astype(np.uint8)
    image[:, :, 0] += np.linspace(0, 30, image.shape[1], dtype=np.uint8)[None, :]
    for x, y, value in [(20, 20, 255), (72, 45, 240), (120, 74, 250)]:
        image[y, x] = value
        image[y - 1 : y + 2, x] = np.maximum(image[y - 1 : y + 2, x], value - 15)
        image[y, x - 1 : x + 2] = np.maximum(image[y, x - 1 : x + 2], value - 15)

    buffer = BytesIO()
    Image.fromarray(image).save(buffer, format="JPEG", quality=96)
    return buffer.getvalue()
