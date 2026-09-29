class Dscope < Formula
  desc "Find what is eating your disk space"
  homepage "https://github.com/dankinsoid/diskscope"
  version "1.0.2"
  sha256 "83c789c8313efe17ca7bbfee998f8c1b386991ee7179d5a6723dbee3124dfff1"
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
