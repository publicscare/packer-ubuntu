# certs/

Put corporate root CA certificates here, e.g. `zscaler-ca.crt`. Every build trusts them inside the guest *before* anything is downloaded over HTTPS. That's needed behind Zscaler or any other TLS-inspecting proxy, or the downloads of `gh`, PowerShell and other GitHub releases fail.

- Formats: PEM or DER, named `*.crt`, `*.pem` or `*.cer`. Windows line endings are fine.
- Everything in this folder except this README and `.gitkeep` is **git-ignored**, so certificates never get pushed.
- To export Zscaler's root on Windows, open `certmgr.msc`, go to **Trusted Root Certification Authorities → Certificates**, find the Zscaler Root CA, then **All Tasks → Export**. Choose *Base-64 encoded X.509 (.CER)*.
- The certificates stay trusted in the finished image, so VMs built from it work on the corporate network too.
