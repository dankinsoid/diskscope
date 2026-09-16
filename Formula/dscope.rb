class Dscope < Formula
  desc "Find what is eating your disk space"
  homepage "https://github.com/dankinsoid/diskscope"
  version "1.0.0"
  sha256 "edcffef38e06b35525426eaacc268121127e289d4b040450da63711ea259f059"
  license "MIT"

  url "https://github.com/dankinsoid/diskscope/releases/download/v#{version}/dscope-#{version}-macos.tar.gz"

  depends_on macos: :sonoma

  def install
    # Homebrew unpacks the tarball and enters its single top-level directory,
    # so the files are already at hand without the versioned prefix.
    bin.install "dscope"
    prefix.install "skills"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/dscope --version")
    system bin/"dscope", "scan", testpath, "--json"
  end
end
