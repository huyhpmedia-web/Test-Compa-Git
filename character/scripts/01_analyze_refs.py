"""Stage 1 -- analyse the three reference photos with MediaPipe.

Writes build/lm_{1,2,3}.json (478 face landmarks, px) and build/seg_{1,2,3}.npy
(per-pixel confidences: background, hair, body-skin, face-skin, clothes, other).
1 = ref_front, 2 = ref_profile, 3 = ref_closeup.
"""
import json
import os
import numpy as np
import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
B = os.path.join(ROOT, "build")
REFS = {"1": "ref_front.jpg", "2": "ref_profile.jpg", "3": "ref_closeup.jpg"}


def main():
    os.makedirs(B, exist_ok=True)
    det = vision.FaceLandmarker.create_from_options(vision.FaceLandmarkerOptions(
        base_options=python.BaseOptions(model_asset_path=os.path.join(ROOT, "models", "face_landmarker.task")),
        output_face_blendshapes=True, output_facial_transformation_matrixes=True, num_faces=1,
        min_face_detection_confidence=0.3, min_face_presence_confidence=0.3))
    seg = vision.ImageSegmenter.create_from_options(vision.ImageSegmenterOptions(
        base_options=python.BaseOptions(model_asset_path=os.path.join(ROOT, "models", "selfie_multiclass.tflite")),
        output_category_mask=True, output_confidence_masks=True))
    for key, fn in REFS.items():
        img = mp.Image.create_from_file(os.path.join(ROOT, "reference", fn))
        w, h = img.width, img.height
        res = det.detect(img)
        lm = np.array([[p.x * w, p.y * h, p.z * w] for p in res.face_landmarks[0]])
        out = {"w": w, "h": h, "landmarks": lm.tolist(),
               "blendshapes": {c.category_name: c.score for c in res.face_blendshapes[0]},
               "matrix": np.array(res.facial_transformation_matrixes[0]).tolist()}
        json.dump(out, open(os.path.join(B, f"lm_{key}.json"), "w"))
        conf = np.stack([np.squeeze(m.numpy_view()) for m in seg.segment(img).confidence_masks], axis=-1)
        np.save(os.path.join(B, f"seg_{key}.npy"), conf.astype(np.float16))
        print(fn, "landmarks", lm.shape, "seg", conf.shape)
    det.close()
    seg.close()


if __name__ == "__main__":
    main()
