# Unreal Engine 3 LibHTTP

LibHTTP is a general purpose library for Unreal Engine 3. It allows you to fetch files stored on web servers.

Based on UE2-LibHTTP by elmuerte: https://github.com/elmuerte/UE2-LibHTTP.

Ported to Unreal Engine 3. Some features have been stripped.

This version of the package has been made specifically for Rising Storm 2: Vietnam!
Some minor tweaks may be necessary for other games!

##### Original UE2 Features **(some might not work in the UE3 version)**:

- Support for HTTP version 1.0 and 1.1
- Support for GET/POST/HEAD/TRACE request methods
- Normal and accelerated transfer modes (accelerated mode creates a performance hit)
- Response and Request Header management
- Cookie management
- Authentication supports (both Basic and Digest methods are supported)
- Support for HTTP proxies
- Graceful handling of connection timeouts
- Automatic decoding of chunked data
- Automatically follows redirects (creates a redirection history)
- Support for multipart/form-data POST data (preferred form)

## TODO

- There might be some bad leftover code from the UE2 -> UE3 refactor.
- Some UE2 specific code was dropped entirely, check if there's a way to bring it back in and if it's even desirable to do so.
