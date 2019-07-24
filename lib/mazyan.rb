require 'pry'

class Pai
  attr_reader :suit, :number, :character

  class InvalidCharacterError < StandardError
  end

  class CannotInitializeError < StandardError
  end

  TILES = {
    "字" => %w(東 南 西 北 白 發 中),
    "萬" => %w(一 二 三 四 五 六 七 八 九),
    "筒" => %w(① ② ③ ④ ⑤ ⑥ ⑦ ⑧ ⑨),
    "索" => %w(1 2 3 4 5 6 7 8 9)
  }

  class << self
    def lookup_table
      @@lookup_table ||= TILES.each_with_object({}) do |(kind, characters), h|
        characters.each_with_index do |character, i|
          h[character] = [kind, i + 1]
        end
      end
    end

    def convert_characters(characters)
      characters = characters.scan(/\w/)
      characters.map { |c| Pai.new(character: c) }
    end
  end

  def initialize(character: nil, suit: nil, number: nil)
    return initialize_by_character(character) if character
    return initialize_by_suit_and_number(suit, number) if suit && number
    raise CannotInitializeError
  end

  def initialize_by_character(character)
    @character = character
    @suit, @number = self.class.lookup_table[character]
    raise InvalidCharacterError unless @suit
  end

  def initialize_by_suit_and_number(suit, number)
    raise CannotInitializeError unless number.between?(1,9)
    @suit, @number = suit, number
    @character = TILES[suit.to_s][number - 1] rescue nil
    raise CannotInitializeError unless @character
  end
end

class Group
  attr_reader :kind, :suit, :number, :is_complete, :is_furou

  def initialize(params)
    @kind          = params[:kind] # 刻順槓嵌
    @suit          = params[:suit]
    @number        = params[:number]
    @is_complete   = params[:is_complete]
    @is_furou      = params[:is_furou] || false

    @is_complete = true if @is_complete.nil?
  end

  def get_machi
    return if is_complete

    case kind
    when "刻" then get_kotu_machi
    when "順" then get_jun_machi
    when "嵌" then get_kanchan_machi
    end
  end

  def get_kotu_machi
    [Pai.new(suit: suit, number: number)]
  end

  def get_jun_machi
    before, after = number - 1, number + 2
    machi = []
    machi << Pai.new(suit: suit, number: before) if before >= 1
    machi << Pai.new(suit: suit, number: after)  if after <= 9
    machi
  end

  def get_kanchan_machi
    [Pai.new(suit: suit, number: number + 1)]
  end

  class << self
    def group_pais(pais: nil, suit: nil, numbers: nil, allow_incomplete: false, allow_kan: false)
      unless suit && numbers
        suits, numbers = pais.map(&:suit), pais.map(&:number)
        return unless all_same?(suits)
        suit = suits.first
      end

      num_of_pais = numbers.size
      return unless num_of_pais.between?(2, 3) || (num_of_pais == 4 && allow_kan)

      return group_same(suit, numbers.first, num_of_pais) if all_same?(numbers)

      return unless suit != '字' && num_of_pais.between?(2, 3)
      numbers = numbers.sort
      return group_consecutive(suit, numbers.first, num_of_pais) if is_consecutive?(numbers)

      return unless num_of_pais == 2 && is_kanchan?(numbers)
      group_kanchan(suit, numbers.first)
    end

    def all_same?(arr)
      arr.uniq.size == 1
    end

    def group_same(suit, number, num_of_pais)
      case num_of_pais
      when 4
        Group.new(kind: "槓", suit: suit, number: number)
      when 3
        Group.new(kind: "刻", suit: suit, number: number)
      when 2
        Group.new(kind: "刻", suit: suit, number: number, is_complete: false)
      else
        nil
      end
    end

    def is_consecutive?(numbers)
      (0...numbers.size - 1).all? { |i| numbers[i] + 1 == numbers[i + 1] }
    end

    def group_consecutive(suit, number, num_of_pais)
      case num_of_pais
      when 3
        Group.new(kind: "順", suit: suit, number: number)
      when 2
        Group.new(kind: "順", suit: suit, number: number, is_complete: false)
      else
        nil
      end
    end

    def is_kanchan?(numbers)
      a, b = numbers
      a + 1 == b - 1
    end

    def group_kanchan(suit, number)
      Group.new(kind: "嵌", suit: suit, number: number, is_complete: false)
    end
  end
  binding.pry
end


class Hand
  def initialize(monzen, furou)

  end

  def display
  end
end

class Mazyan
  def self.display(monzen, furou = [])
  end
end