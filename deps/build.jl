using Pkg

@info("Adding unregistered package JSCall")

Pkg.add(PackageSpec(url="https://github.com/SimonDanisch/JSCall.jl"))

@info("Adding unregistered package ShaderAbstraction")

Pkg.add(PackageSpec(url="https://github.com/SimonDanisch/ShaderAbstractions.jl"))

@info("Done building.")
