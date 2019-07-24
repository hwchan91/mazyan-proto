require 'mazyan'

RSpec.describe Mazyan do
  describe "display" do
    it "works" do
      disp = Mazyan.display(%w(01 02 03 04 05 06 07 11 19 21 29 31 39))
      expect(disp).to eq(%w(東 南 西 北 白 發 中 一 九 ① ⑨ 1 9))
    end
  end
end