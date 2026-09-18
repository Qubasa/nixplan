# The throwaway dm-verity pair this folder's image is signed with, published
# here exactly as nixpkgs publishes the snakeoil ssh key the guest authorizes:
# the public half is provisioning the guest installs under /etc/verity.d and the
# private half is an argument of the image build, so neither is a plan fact and
# neither authorizes anything outside an offline throwaway guest. Minted once
# with `openssl req -new -x509 -nodes`; an evaluation mints nothing, running no
# program, and a per-run pair would be a key input of every snapshot cut.
#
# One file for both halves because the two sides need one: the guest installs
# the certificate and this folder's deployment hands the build both, and a pair
# whose halves were copied apart is a pair that can disagree.
{ writeText }:
{
  certificate = writeText "planner-e2e-throwaway.crt" ''
    -----BEGIN CERTIFICATE-----
    MIIDRzCCAi+gAwIBAgIULhgKixXbxPwEOr8r6jJAhuhFEdwwDQYJKoZIhvcNAQEL
    BQAwMjEwMC4GA1UEAwwncGxhbm5lciBlbmQtdG8tZW5kIHRocm93YXdheSB2ZXJp
    dHkga2V5MCAXDTI2MDkxNzIxMzI1NFoYDzIxMjYwODI0MjEzMjU0WjAyMTAwLgYD
    VQQDDCdwbGFubmVyIGVuZC10by1lbmQgdGhyb3dhd2F5IHZlcml0eSBrZXkwggEi
    MA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDsTxHl6xKM/pWw0/kGISMx80CA
    hwmhONLXNyIxr7XSv0XNw4uqjmmnqsQufPpTe3UaAoKjQmN67LcQBsgtZ3BvdHH6
    X8bDnHQNpKn80ktAmwLVj0xrK9hyfg+0g+b+SPob9d0gry2hfaYzfUD5MrJ5lUtv
    UfANCTFH1i4dXfM3bvObT9kHqjnGi5u/HFAPNyJTILOEHo690Cyj9ulQ5KKS7Ivd
    WuDiJLNl2gEY0QborDejtIoQeZq2PAHIgiP3z6c0KLrEkyWT5P54NxEnQpela5UL
    X9UNbAJAeIn8VFyhUc/skFfqzMiW6OwuhUIn8AQWYKQIfzFNennsfYZx0bY5AgMB
    AAGjUzBRMB0GA1UdDgQWBBQoV5fHGjaUFZ3d7MWCGeqVwb67hzAfBgNVHSMEGDAW
    gBQoV5fHGjaUFZ3d7MWCGeqVwb67hzAPBgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3
    DQEBCwUAA4IBAQBrQhnWA7tDMTEAgZ+3JVfG39KxT4JO7pCq6Pgob6mYptZ8MehS
    eiRKbjfY+Gz+zBIlclklvK7HpKODEWAHub8Qu7PjaodF7vjqmunVj6YP/H+j8DnY
    Qm0jENdpeJZkRaMVM0JZiRkVH3hJSwYUpGRwEm3gGKOLf+i6MVjw4tOys7+EVwm9
    OposMbU6LL0orEx9bGN7J68GyX+Qxr1J35rUa94Ac30gFmaY9GFEm/GjD7jWsbGS
    FIfTCWeXtqzfJnksgv1pn6zyIt3XnqYYccF5dOCDGrAOjx/jYFpi8iD7atDsGdtC
    jErF5yT5O54cqEZaUP1MB/JOONCC8ZL9pNQF
    -----END CERTIFICATE-----
  '';

  privateKey = writeText "planner-e2e-throwaway.key" ''
    -----BEGIN PRIVATE KEY-----
    MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDsTxHl6xKM/pWw
    0/kGISMx80CAhwmhONLXNyIxr7XSv0XNw4uqjmmnqsQufPpTe3UaAoKjQmN67LcQ
    BsgtZ3BvdHH6X8bDnHQNpKn80ktAmwLVj0xrK9hyfg+0g+b+SPob9d0gry2hfaYz
    fUD5MrJ5lUtvUfANCTFH1i4dXfM3bvObT9kHqjnGi5u/HFAPNyJTILOEHo690Cyj
    9ulQ5KKS7IvdWuDiJLNl2gEY0QborDejtIoQeZq2PAHIgiP3z6c0KLrEkyWT5P54
    NxEnQpela5ULX9UNbAJAeIn8VFyhUc/skFfqzMiW6OwuhUIn8AQWYKQIfzFNenns
    fYZx0bY5AgMBAAECggEAHZaw+Qb8Jadi+ucv0TKpA4If23gNHqDM1aHTqEEGFUNZ
    7C/F9y8pz5K0SdXgSj+1I/KYhPS1HBkzus/+lKDVFT+RXfZMHwYiCetKVZvHTGmc
    az0sJmcxDPT35nR1ofVlS8b3TzZgEk53Vw8h6ZINgufMsD2kPx2djA8nawnugEwo
    mLDPPchRGkcMu8iPb6B/eIboKgdqS2Z7nfF0/CdhKfjWTgG/t2sSvxV04Ww3bmXw
    KcP4uw5qo+7d0i8Laoroc13Qmj24rhg9u7ZcSAAbRi5KkVSStFeTvCXd+j5Ufj2v
    KT/5dRJd5hbnnK94mP/BsGIpcDHw4Rv5wLjmMywd+QKBgQD9xO4kMivLKkmTnF3W
    dR4V+Q1CZmVpsUN0YjpeEe/UEZXnwM8D3wDDChqhyCAEz7oKoZRBaim3mCIP5E1j
    e2+cFdrGuJA+tw9Vvxfhf2CHJy0uVKHKFUNFpugxS2KdK4YG4GtnflP1If2wFycT
    H59W2N3P/8C5tOtEglsVZCjN4wKBgQDuYtkBL1qnLsC4nt3SId4tU3NRpAHCsQ6H
    U7wUBjq1YYSNz40erRNGVODA/uwBdE8/zEbD2DDjG08cmR6tWA1XWsFhy4yDSd6W
    MZm6GG25MiMsoy158EntdmLrj83JTOw/oMrSMVQbwaM9+dJx50xJp/VzUDQrgXJ7
    FhIA3ismMwKBgHskZtMVrX6nBJEmnbqFlpXfBvojqi6BoFQHnn8rgQ+NgQq22z3r
    pvj+HDJJZJAxJPwnsEOV+qxmnJDNnmgZ6+z4BfPMd+KW/lADrNj18Kdk8V28H85q
    Rvyzo5TYGgBesGkB2dycxqz7U5lxgrqa670++1QFrUXwbwINp5lXwx01AoGBAKbj
    itqahVOPlppplg+7aCjBSHV6ZUUg4XP6Oiymo8lBySPijwBP2LOfTm2uyhjGjYiz
    gUMwgiEsiDkUNXbTsxtZzRKjBu8O8wahGOdAnOhPYnKolnjMsWTOQbh6R25LLQXq
    krOOlzyLVrZXxG27qRvTuzGMj8l5aWUkcVwsLXcjAoGBALGo8OzusUJZ28HaleJ2
    xff94A1CpKLLFfkxwgJKO0ys7X0a8xVsQli1UnTQ/uJ+qRfFpT0e1DFGGmy67pP/
    SwMdMcPUVVX3HQQyqXQN/phaUhv6Yi7uYTQenA9Io06Czicg6e1lCTDxaQfQKZQr
    aH7QRq/gfPCL813QJvMk3A+s
    -----END PRIVATE KEY-----
  '';
}
