# frozen_string_literal: true

RSpec.describe TextUtils do
  describe '.maybe_rtl_reverse_lines' do
    it 'reorders each line of a right-to-left text on its own, so the lines keep their order' do
      lines = ['שלום First paragraph', 'תודה Second paragraph']

      result = described_class.maybe_rtl_reverse_lines(lines.join("\n")).split("\n")

      expect(result).to eq(lines.map { |line| described_class.maybe_rtl_reverse(line) })
      expect(result.first).to include('First paragraph')
      expect(result.second).to include('Second paragraph')
    end

    it 'leaves a left-to-right text as it is' do
      expect(described_class.maybe_rtl_reverse_lines("First paragraph\n\nSecond paragraph"))
        .to eq("First paragraph\n\nSecond paragraph")
    end
  end
end
