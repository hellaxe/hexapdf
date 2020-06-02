# -*- encoding: utf-8 -*-

require 'test_helper'
require 'hexapdf/document'
require 'hexapdf/type/acro_form/field'

describe HexaPDF::Type::AcroForm::Field do
  before do
    @doc = HexaPDF::Document.new
    @field = @doc.add({}, type: :XXAcroFormField)
  end

  it "must always be an indirect object" do
    assert(@field.must_be_indirect?)
  end

  it "resolves inherited field values" do
    assert_nil(@field[:FT])

    @field[:Parent] = {FT: :Tx}
    assert_equal(:Tx, @field[:FT])

    @field[:FT] = :Ch
    assert_equal(:Ch, @field[:FT])
  end

  it "has convenience methods for accessing the field flags" do
    assert_equal([], @field.flags)
    refute(@field.flagged?(:required))
    @field.flag(:required, 2)
    assert(@field.flagged?(2))
    assert_equal(6, @field[:Ff])
  end

  it "returns the field type" do
    assert_nil(@field.field_type)

    @field[:FT] = :Tx
    assert_equal(:Tx, @field.field_type)
  end

  it "returns the field name" do
    assert_nil(@field.field_name)
    @field[:T] = 'test'
    assert_equal('test', @field.field_name)
  end

  it "returns the full name of the field" do
    assert_nil(@field.full_field_name)

    @field[:T] = "Test"
    assert_equal("Test", @field.full_field_name)

    @field[:Parent] = {}
    assert_equal("Test", @field.full_field_name)

    @field[:Parent] = {T: 'Parent'}
    assert_equal("Parent.Test", @field.full_field_name)
  end

  it "returns whether the field is a terminal field" do
    assert(@field.terminal_field?)

    @field[:Kids] = []
    assert(@field.terminal_field?)

    @field[:Kids] = [{Subtype: :Widget}]
    assert(@field.terminal_field?)

    @field[:Kids] = [{FT: :Tx}]
    refute(@field.terminal_field?)
  end

  describe "each_widget" do
    it "yields a wrapped instance of self if a single widget is embedded" do
      @field[:Subtype] = :Widget
      @field[:Rect] = [0, 0, 0, 0]
      widgets = @field.each_widget.to_a
      assert_kind_of(HexaPDF::Type::Annotations::Widget, *widgets)
      assert_same(@field.data, widgets.first.data)
    end

    it "yields all widgets in the /Kids array" do
      @field[:Kids] = [{Subtype: :Widget, Rect: [0, 0, 0, 0], X: 1}]
      widgets = @field.each_widget.to_a
      assert_kind_of(HexaPDF::Type::Annotations::Widget, *widgets)
      assert_equal(1, widgets.first[:X])
    end
  end

  describe "create_widget" do
    before do
      @page = @doc.pages.add
    end

    it "sets all required widget keys" do
      widget = @field.create_widget(@page)
      assert_equal(:Annot, widget.type)
      assert_equal(:Widget, widget[:Subtype])
      assert_equal([0, 0, 0, 0], widget[:Rect])
    end

    it "sets the additionally specified keys on the widget" do
      widget = @field.create_widget(@page, X: 5)
      assert_equal(5, widget[:X])
    end

    it "adds the new widget to the given page's annotations" do
      widget = @field.create_widget(@page)
      assert_equal([widget], @page[:Annots].value)
    end

    it "populates the field with the widget data if there is no widget" do
      widget = @field.create_widget(@page)
      assert_same(widget.data, @field.data)
      assert_nil(@field[:Kids])
    end

    it "extracts an embedded widget into a standalone object if necessary" do
      widget1 = @field.create_widget(@page, Rect: [1, 2, 3, 4])
      widget2 = @field.create_widget(@doc.pages.add, Rect: [2, 1, 4, 3])
      kids = @field[:Kids]

      assert_equal(2, kids.length)
      refute_same(widget1, kids[0])
      assert_same(widget2, kids[1])
      assert_nil(@field[:Rect])
      assert_equal([1, 2, 3, 4], kids[0][:Rect].value)
      assert_equal([2, 1, 4, 3], kids[1][:Rect].value)

      refute_equal([widget1], @page[:Annots].value)
      assert_equal([kids[0]], @page[:Annots].value)
    end

    it "fails if called on a non-terminal field" do
      @field[:Kids] = [{FT: :Tx}]
      assert_raises(HexaPDF::Error) { @field.create_widget(@page) }
    end
  end

  describe "perform_validation" do
    before do
      @field[:FT] = :Tx
    end

    it "requires the /FT key to be present for terminal fields" do
      assert(@field.validate)

      @field.delete(:FT)
      refute(@field.validate)

      @field[:Kids] = [{}]
      assert(@field.validate)
    end

    it "doesn't allow periods in partial field names" do
      assert(@field.validate)

      @field[:T] = "Test"
      assert(@field.validate)

      @field[:T] = "Te.st"
      refute(@field.validate)
    end
  end
end