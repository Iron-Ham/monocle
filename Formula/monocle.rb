class Monocle < Formula
  desc "Read-only Swift code inspection tool built on SourceKit-LSP"
  homepage "https://github.com/SwiftedMind/monocle"
  url "https://github.com/SwiftedMind/monocle.git", branch: "main", revision: "a185c48492e7d69c42e2a4ebae3410d299864882"
  version "0.1.0"
  head "https://github.com/SwiftedMind/monocle.git", branch: "main"
  license "MIT"

  depends_on xcode: "26.0"

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release"
    binary_path = Dir[".build/*/release/monocle", ".build/release/monocle"].first
    odie "monocle build artifact not found" if binary_path.nil?
    bin.install binary_path
  end

  test do
    output = shell_output("#{bin}/monocle version")
    assert_match "monocle 0.1.0", output
  end
end
