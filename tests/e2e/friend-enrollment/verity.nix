# The throwaway dm-verity pair the image of this folder's account-deployed
# entry is signed with - the machine that entry runs on is a machine whose
# scope is `user`, and an unsigned image such an account attaches escalates to
# an interactive polkit action a non-interactive run reads as a hard failure.
# The public half is provisioning the guest installs under /etc/verity.d and
# the private half is an argument of this folder's build, so neither is a plan
# fact and neither authorizes anything outside an offline throwaway guest.
# Minted once with `openssl req -new -x509 -nodes`; an evaluation mints
# nothing, running no program, and a per-run pair would be a key input of every
# snapshot cut.
#
# A pair of its own rather than the one the other account-deployed folder
# holds: `tests/unit/layers.nix` refuses a file of one end-to-end folder that
# names another, so a shared fixture would have to move out of both folders,
# and a throwaway whose halves were copied apart is a pair that can disagree.
# systemd enumerates every `*.crt` under /etc/verity.d, so two installed
# certificates admit two folders' images and neither refuses the other's.
#
# One file for both halves because the two sides need one: the guest installs
# the certificate and this folder's deployment hands the build both.
{ writeText }:
{
  certificate = writeText "planner-e2e-friend-enrollment.crt" ''
    -----BEGIN CERTIFICATE-----
    MIIDVTCCAj2gAwIBAgIUNqPxgKmuH6E1chV8JI5IdvhAmX0wDQYJKoZIhvcNAQEL
    BQAwOTE3MDUGA1UEAwwucGxhbm5lciBmcmllbmQgZW5yb2xsbWVudCB0aHJvd2F3
    YXkgdmVyaXR5IGtleTAgFw0yNjA5MTgwMTMyMjFaGA8yMTI2MDgyNTAxMzIyMVow
    OTE3MDUGA1UEAwwucGxhbm5lciBmcmllbmQgZW5yb2xsbWVudCB0aHJvd2F3YXkg
    dmVyaXR5IGtleTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBANKv2f6b
    MZPC4+k1F76uqq2WJOdmpRkhPaONDgqtaJAlE+OLQYnmJK4dwPrCPx6bPZI2feK9
    fnp30cBPcakd/XpYrny12t++5aruL9ZgoW2SkW/5w5lPDExADctriLbaJ0KUGTdA
    7naVTpyRkuRldv1SFV+KXGE5KscJw4jECbQnr0tZyGhZbkhM0LWbAKjK68lTeTg5
    0sARYeWVxdiwzhFWD1rSg1tI2hK++gryJFlhs+5PlZp6g96/Zu92/W43s52lezk1
    MdUji4nTo9dFcMJP9foLa6juPI30pwXvclPUzyZZngkz3N5riKh3Zh3BTZ+CHopu
    kaIC9dkpjJLgoi8CAwEAAaNTMFEwHQYDVR0OBBYEFJieM6+TsVSB0R0v8E9OVHba
    3XE5MB8GA1UdIwQYMBaAFJieM6+TsVSB0R0v8E9OVHba3XE5MA8GA1UdEwEB/wQF
    MAMBAf8wDQYJKoZIhvcNAQELBQADggEBADHkhDPvlTbrqviM8Vk2WV/s95iIS7WL
    o00lkKTDRblGnHjty1M1uHPUFvh4tvnBr3IVxzGNV+owc7EkHf1FOUWemwu9SurI
    ErAb8VlLED3T/RyKwXyzc1BvDHHqepTfy6f3eNqjPUZVzosrvgpF1pRYyYtZdrpe
    0Qxy7O7j0F27VXo+6glzjD+VnIJ2G3sG0MX9nK3G3rglWsgVjdKo98P8NXt0PJL5
    Qhn/2iyL7PMhktkMRFL71cYhmK+bX+QytBA7/KkaGy7ks+vMqeMkUKG43kwd9S2x
    6hTGWrv9OpR9hxLvVA1cGz5G+WR4qO8GHe+EOSjkguD9PnO/Y24mCeA=
    -----END CERTIFICATE-----
  '';

  privateKey = writeText "planner-e2e-friend-enrollment.key" ''
    -----BEGIN PRIVATE KEY-----
    MIIEvwIBADANBgkqhkiG9w0BAQEFAASCBKkwggSlAgEAAoIBAQDSr9n+mzGTwuPp
    NRe+rqqtliTnZqUZIT2jjQ4KrWiQJRPji0GJ5iSuHcD6wj8emz2SNn3ivX56d9HA
    T3GpHf16WK58tdrfvuWq7i/WYKFtkpFv+cOZTwxMQA3La4i22idClBk3QO52lU6c
    kZLkZXb9UhVfilxhOSrHCcOIxAm0J69LWchoWW5ITNC1mwCoyuvJU3k4OdLAEWHl
    lcXYsM4RVg9a0oNbSNoSvvoK8iRZYbPuT5WaeoPev2bvdv1uN7OdpXs5NTHVI4uJ
    06PXRXDCT/X6C2uo7jyN9KcF73JT1M8mWZ4JM9zea4iod2YdwU2fgh6KbpGiAvXZ
    KYyS4KIvAgMBAAECggEAaDi0YlYcLsecXbs1XU7jQI6C//NPXYCLkNHQreh9Tr0A
    uzGigJhX8cfnNESN29KYoTESke0CWYvXN0Y1aB7dSr3+xtNhDAjPbQB5qpdPk7gK
    +PT5VOf9IeUXzdaKoUWGYVGIrcQRkpimdB4xJ4mn1IVb7FCyBSg16JMEZq3vTO3k
    hGc7LwY4mxofFSFCAmDQXcHIUK9qi8FRLelKKB3EAjpdcxVEqlfrj8aejMcqjnfN
    J8lTYPYLQoNVswygGO5FoX1bY36HO/RoggB5Ci2j5BxwaeOoss1LJnImmxJrho2Z
    GsV0eWBJmB31MWXvlhIq058ZeHJuOeUoYwJnohDC5QKBgQD2dZ6evRIcGE2+Cljb
    FZWmvMwNtnt3KYtwtMR+6DUbrG1yD3xBIa/NprzIvNZW9F7dmFd+XNmAUbl49eyX
    C9cZX8mmnSOnQ/D/9unrKCxJQspb+fPr1ugsSFS0adyti0y4PGxWujpd9L3IEUYL
    quZPt4A9tXH6694bTKTkCnLdKwKBgQDa17scWoOeGARUnU14H7AZ/SY/zM9GLucX
    1JAphJEIO6F7RM0HGGJy9Mg3zwVamzaySKLTxFj17tUKcUfCp3wEw1tS+WnajgKV
    D+0g4Ho8rrJh357ybB+kAV+FF3KfkUJau9atR/LX3AqEifsf1UBiKmbLaJCXUymX
    47FsIAS1DQKBgQDU/HiDvek0llw460A2tMSLP4UoJJc2N5TlZZKaCZo7vBspAvDi
    aHZBRuLGp0qkArMo1UpnTV45YmbifcRkFDtjFkBx2ELDfhd7XKpyKll7RlkSe0Os
    gCBMhIWPFB09bLB0VuNZX76pC6Qmjab21k4Kfg45ReCmc8eR1/53hAAX2QKBgQC5
    CVFvHuVMpjf7J2oaWIi44MAXj9/uErhZAOTIBgvvLyRRqxHEnwyW8HveHFAFlVmB
    E0OB1PH3N/KwOqoXXy/QgzHTjYnAPvTV/rpcYxFX/8paUQ7/IQb70CFo0jOb0eGO
    AGb66uvdMnM+L8DC4LfoiLuT35zqJmnzwJUCvGvefQKBgQC2DZy/k5UmhwSEmpfv
    tWgh1pMFxyfMGu/RM1Z+BrIW7H6g99+4n8f9qEfJTFle7vajsrf1sSq7wsvgOWEY
    sN8kKENJrIq6GZkTZVrIZPeYD9/pNey8UyFBg54dzO7IZJlvHvcUvI+AscqBL1fh
    k3qKWmuJdQXOPGhSzn59CoxI0w==
    -----END PRIVATE KEY-----
  '';
}
