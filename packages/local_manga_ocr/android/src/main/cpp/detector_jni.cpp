#include "detector_engine.hpp"
#include <jni.h>
#include <memory>
#include <new>

namespace {
void fail(JNIEnv* env, const char* type, const char* message) {
  if (!env->ExceptionCheck()) {
    auto exception = env->FindClass(type);
    if (exception) { env->ThrowNew(exception, message); env->DeleteLocalRef(exception); }
  }
}
}

extern "C" JNIEXPORT jlong JNICALL
Java_moe_matthew_mekuru_ocr_ComicTextDetectorNative_create(JNIEnv* env, jobject, jstring path, jint threads) {
  const char* text = env->GetStringUTFChars(path, nullptr);
  if (!text) return 0;
  try {
    std::string model(text);
    env->ReleaseStringUTFChars(path, text); text = nullptr;
    return reinterpret_cast<jlong>(new ComicDetector(model, threads));
  } catch (const std::bad_alloc&) {
    fail(env, "java/lang/OutOfMemoryError", "low_memory");
  } catch (const std::exception& error) {
    fail(env, "java/lang/IllegalStateException", error.what());
  }
  if (text) env->ReleaseStringUTFChars(path, text);
  return 0;
}

extern "C" JNIEXPORT jobjectArray JNICALL
Java_moe_matthew_mekuru_ocr_ComicTextDetectorNative_forward(JNIEnv* env, jobject, jlong pointer, jfloatArray pixels) {
  try {
    if (!pointer || env->GetArrayLength(pixels) != 3 * 1024 * 1024) {
      throw std::runtime_error("invalid_detector_input");
    }
    const int shape[] = {1, 3, 1024, 1024};
    cv::Mat input(4, shape, CV_32F);
    env->GetFloatArrayRegion(pixels, 0, 3 * 1024 * 1024, input.ptr<float>());
    if (env->ExceptionCheck()) return nullptr;
    const auto result = reinterpret_cast<ComicDetector*>(pointer)->run(input);
    auto arrayClass = env->FindClass("[F");
    if (!arrayClass) return nullptr;
    auto arrays = env->NewObjectArray(3, arrayClass, nullptr);
    env->DeleteLocalRef(arrayClass);
    if (!arrays) return nullptr;
    for (int i = 0; i < 3; ++i) {
      const auto count = static_cast<jsize>(result[i].total());
      auto array = env->NewFloatArray(count);
      if (!array) return nullptr;
      env->SetFloatArrayRegion(array, 0, count, result[i].ptr<float>());
      env->SetObjectArrayElement(arrays, i, array);
      env->DeleteLocalRef(array);
      if (env->ExceptionCheck()) return nullptr;
    }
    return arrays;
  } catch (const std::bad_alloc&) {
    fail(env, "java/lang/OutOfMemoryError", "low_memory");
  } catch (const std::exception& error) {
    fail(env, "java/lang/IllegalStateException", error.what());
  }
  return nullptr;
}

extern "C" JNIEXPORT void JNICALL
Java_moe_matthew_mekuru_ocr_ComicTextDetectorNative_destroy(JNIEnv*, jobject, jlong pointer) {
  delete reinterpret_cast<ComicDetector*>(pointer);
}
