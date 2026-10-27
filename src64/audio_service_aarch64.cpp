/*
 * Minimal aarch64 reimplementation of AOSP
 *   hardware/interfaces/audio/common/all-versions/default/service/service.cpp
 * (the "audiohalservice" loader shell), reduced to what Waydroid's vendor
 * image actually ships in 64-bit: the HIDL 4.0 audio + effect passthrough
 * implementations.
 *
 * Instead of pulling the whole AOSP header tree / hidl-gen output, this file
 * resolves libhidlbase's exported __attribute__((warn_unused_result))
 * status_t registerPassthroughServiceImplementation(const std::string&,
 *     const std::string&, const std::string&)
 * at runtime via dlsym on its mangled name, which is exactly what the original
 * 32-bit /vendor/bin/hw/android.hardware.audio.service links against.
 *
 * Original symbol (seen as UND in the 32-bit binary and as T in
 * /system/lib64/libhidlbase.so):
 *   _ZN7android8hardware40registerPassthroughServiceImplementationERKNSt3__1
 *   12basic_stringIcNS1_11char_traitsIcEENS1_9allocatorIcEEEES9_S9_
 */

#include <android/log.h>
#include <dlfcn.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>

#include <string>
#include <vector>

#define LOG_TAG "audiohalservice"
#define ALOGI(...)                                                            \
    do {                                                                      \
        __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__);           \
        fprintf(stdout, "I/" LOG_TAG ": " __VA_ARGS__);                        \
        fprintf(stdout, "\n");                                                 \
        fflush(stdout);                                                        \
    } while (0)
#define ALOGE(...)                                                            \
    do {                                                                      \
        __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__);          \
        fprintf(stderr, "E/" LOG_TAG ": " __VA_ARGS__);                        \
        fprintf(stderr, "\n");                                                 \
        fflush(stderr);                                                        \
    } while (0)

namespace {

constexpr const char* kLibHidlbase = "libhidlbase.so";
// size_t is 'm' (unsigned long) on LP64 and 'j' (unsigned int) on ILP32, so the
// mangled name of configureRpcThreadpool() differs between the 32-bit original
// and this rebuild. Try both.
constexpr const char* kSymConfigureRpcThreadpool64 =
        "_ZN7android8hardware22configureRpcThreadpoolEmb";
constexpr const char* kSymConfigureRpcThreadpool32 =
        "_ZN7android8hardware22configureRpcThreadpoolEjb";
constexpr const char* kSymJoinRpcThreadpool =
        "_ZN7android8hardware17joinRpcThreadpoolEv";
constexpr const char* kSymRegisterPassthrough =
        "_ZN7android8hardware40registerPassthroughServiceImplementation"
        "ERKNSt3__112basic_stringIcNS1_11char_traitsIcEENS1_9allocatorIcEEE"
        "ES9_S9_";

using ConfigureRpcThreadpoolFn = void (*)(size_t, bool);
using JoinRpcThreadpoolFn = void (*)();
using RegisterPassthroughFn = int (*)(const std::string&, const std::string&,
                                      const std::string&);

}  // namespace

int main(int /*argc*/, char** /*argv*/) {
    signal(SIGPIPE, SIG_IGN);

    void* hidl = dlopen(kLibHidlbase, RTLD_NOW);
    if (hidl == nullptr) {
        ALOGE("dlopen(%s) failed: %s", kLibHidlbase, dlerror());
        return 1;
    }

    auto configureRpcThreadpool =
            reinterpret_cast<ConfigureRpcThreadpoolFn>(dlsym(hidl, kSymConfigureRpcThreadpool64));
    if (!configureRpcThreadpool) {
        configureRpcThreadpool = reinterpret_cast<ConfigureRpcThreadpoolFn>(
                dlsym(hidl, kSymConfigureRpcThreadpool32));
    }
    auto joinRpcThreadpool =
            reinterpret_cast<JoinRpcThreadpoolFn>(dlsym(hidl, kSymJoinRpcThreadpool));
    auto registerPassthrough = reinterpret_cast<RegisterPassthroughFn>(
            dlsym(hidl, kSymRegisterPassthrough));

    if (!configureRpcThreadpool || !joinRpcThreadpool || !registerPassthrough) {
        ALOGE("missing libhidlbase symbols (conf=%p join=%p reg=%p): %s",
              reinterpret_cast<void*>(configureRpcThreadpool),
              reinterpret_cast<void*>(joinRpcThreadpool),
              reinterpret_cast<void*>(registerPassthrough), dlerror());
        return 1;
    }

    configureRpcThreadpool(16, true /*callerWillJoin*/);

    // 64-bit implementations present in this vendor image:
    //   /vendor/lib64/hw/android.hardware.audio@4.0-impl.so        -> HIDL_FETCH_IDevicesFactory
    //   /vendor/lib64/hw/android.hardware.audio.effect@4.0-impl.so -> HIDL_FETCH_IEffectsFactory
    const std::string kDevicesFactory = "android.hardware.audio@4.0::IDevicesFactory";
    const std::string kEffectsFactory = "android.hardware.audio.effect@4.0::IEffectsFactory";

    int rc = registerPassthrough(kDevicesFactory, kDevicesFactory, "default");
    if (rc != 0) {
        ALOGE("Could not register %s (status=%d)", kDevicesFactory.c_str(), rc);
        return 1;
    }
    ALOGI("Registered %s", kDevicesFactory.c_str());

    // Effects are mandatory for the framework but not for booting; do not exit
    // on failure, just report it.
    rc = registerPassthrough(kEffectsFactory, kEffectsFactory, "default");
    if (rc != 0) {
        ALOGE("Could not register %s (status=%d)", kEffectsFactory.c_str(), rc);
    } else {
        ALOGI("Registered %s", kEffectsFactory.c_str());
    }

    ALOGI("audio HAL service ready, joining rpc threadpool");
    joinRpcThreadpool();
    return 0;
}
