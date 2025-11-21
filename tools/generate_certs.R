#!/usr/bin/env Rscript

# Generate self-signed TLS certificates for development/testing
# Prefers mkcert (for locally-trusted certificates) but falls back to openssl

generate_certs <- function(dir = NULL, domain = "localhost", days = 365, force = FALSE) {
    # Check if mkcert is available (preferred method)
    mkcert_path <- Sys.which("mkcert")
    openssl_path <- Sys.which("openssl")

    if (!nzchar(mkcert_path) && !nzchar(openssl_path)) {
        stop("Neither mkcert nor openssl found in PATH. Please install one of them.")
    }

    # Default to a temporary directory when no explicit directory is provided
    if (is.null(dir)) {
        dir <- file.path(tempdir(), "mangoro-certs")
        message("No output directory provided; using temporary directory: ", dir)
    }

    # Create directory
    if (!dir.exists(dir)) {
        dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    }

    cert_file <- file.path(dir, "cert.pem")
    key_file <- file.path(dir, "key.pem")

    # Check if files already exist
    if (!force && (file.exists(cert_file) || file.exists(key_file))) {
        stop("Certificate or key file already exists in ", dir, ". Use force = TRUE to overwrite.")
    }

    # Try mkcert first (creates locally-trusted certificates)
    if (nzchar(mkcert_path)) {
        message("Using mkcert for locally-trusted certificate generation...")

        # mkcert generates files like "localhost+2.pem" and "localhost+2-key.pem"
        # We'll generate them in the target directory
        wd <- getwd()
        tryCatch(
            {
                setwd(dir)
                system2(
                    "mkcert",
                    c("-cert-file", "cert.pem", "-key-file", "key.pem", domain, "*.local", "127.0.0.1", "::1"),
                    stdout = FALSE,
                    stderr = FALSE
                )
                setwd(wd)

                if (file.exists(cert_file) && file.exists(key_file)) {
                    message(
                        "✓ Certificates generated with mkcert!\n",
                        "  Certificate: ", normalizePath(cert_file), "\n",
                        "  Key: ", normalizePath(key_file), "\n",
                        "  These are locally-trusted development certificates."
                    )
                    return(list(
                        cert = normalizePath(cert_file),
                        key = normalizePath(key_file),
                        dir = normalizePath(dir),
                        method = "mkcert"
                    ))
                }
            },
            error = function(e) {
                setwd(wd)
                NULL
            }
        )
    }

    # Fall back to openssl
    if (nzchar(openssl_path)) {
        message("Using openssl for self-signed certificate generation...")

        # Step 1: Generate private key
        system2(
            "openssl",
            c("genrsa", "-out", key_file, "2048"),
            stdout = FALSE,
            stderr = FALSE
        )

        # Step 2: Create temporary CSR (Certificate Signing Request)
        csr_file <- file.path(dir, "csr.pem")
        subj <- paste0(
            "/C=US/ST=State/L=City/O=Organization/CN=",
            domain
        )

        system2(
            "openssl",
            c("req", "-new", "-key", key_file, "-out", csr_file, "-subj", subj),
            stdout = FALSE,
            stderr = FALSE
        )

        # Step 3: Generate self-signed certificate with subjectAltName
        config_file <- file.path(dir, "openssl.conf")
        san <- paste0("DNS:", domain, ",DNS:*.local,DNS:localhost,IP:127.0.0.1")
        cat(paste0("subjectAltName=", san), file = config_file)

        # Generate self-signed certificate
        if (.Platform$OS.type == "windows") {
            cmd <- sprintf(
                'openssl x509 -req -days %d -in "%s" -signkey "%s" -out "%s" -extfile "%s"',
                days, csr_file, key_file, cert_file, config_file
            )
            system(cmd, ignore.stdout = TRUE, ignore.stderr = TRUE)
        } else {
            system2(
                "openssl",
                c(
                    "x509", "-req", "-days", as.character(days),
                    "-in", csr_file, "-signkey", key_file, "-out", cert_file,
                    "-extfile", config_file
                ),
                stdout = FALSE,
                stderr = FALSE
            )
        }

        # Clean up temporary files
        unlink(csr_file)
        unlink(config_file)

        if (file.exists(cert_file) && file.exists(key_file)) {
            message(
                "✓ Self-signed certificates generated with openssl!\n",
                "  Certificate: ", normalizePath(cert_file), "\n",
                "  Key: ", normalizePath(key_file), "\n",
                "  Note: Browsers will show a security warning for self-signed certificates.\n",
                "  For locally-trusted certs, install mkcert: https://github.com/FiloSottile/mkcert"
            )
            return(list(
                cert = normalizePath(cert_file),
                key = normalizePath(key_file),
                dir = normalizePath(dir),
                method = "openssl"
            ))
        }
    }

    stop("Failed to generate certificates")
}

# Parse command line arguments
args <- commandArgs(trailingOnly = TRUE)

dir_val <- ".certs"
domain_val <- "localhost"
days_val <- 365
force_val <- FALSE

i <- 1
while (i <= length(args)) {
    arg <- args[i]
    if (arg == "--dir" && i < length(args)) {
        dir_val <- args[i + 1]
        i <- i + 2
    } else if (arg == "--domain" && i < length(args)) {
        domain_val <- args[i + 1]
        i <- i + 2
    } else if (arg == "--days" && i < length(args)) {
        days_val <- as.integer(args[i + 1])
        i <- i + 2
    } else if (arg == "--force") {
        force_val <- TRUE
        i <- i + 1
    } else if (arg == "--help" || arg == "-h") {
        message(
            "Generate self-signed TLS certificates\n\n",
            "Usage: Rscript tools/generate_certs.R [options]\n\n",
            "Options:\n",
            "  --dir DIR        Output directory (default: temporary dir)\n",
            "  --domain DOMAIN  Domain name for cert (default: localhost)\n",
            "  --days DAYS      Validity in days (default: 365)\n",
            "  --force          Overwrite existing files\n",
            "  --help           Show this help\n"
        )
        quit(save = "no", status = 0)
    } else {
        i <- i + 1
    }
}

# Generate certificates
result <- generate_certs(dir = dir_val, domain = domain_val, days = days_val, force = force_val)
invisible(result)
