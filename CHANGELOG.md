## 0.0.1

* `SharedPreferencesCacheStore`: `SharedPreferencesAsync`-backed `CacheStore` with per-env key; blocked storage degrades to load-null/save-noop and never throws.
* Device targeting collector: platform, build-stripped appVersion, locale/country; customAttrs from explicit input.
* `ConfigWireFlutter.createConfigWire` one-call factory returning a wired `ConfigWire`.
