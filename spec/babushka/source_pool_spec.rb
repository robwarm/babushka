require 'spec_helper'
require 'source_support'

describe Babushka::SourcePool do

  describe 'default sources' do
    describe 'types' do
      it "should classify the anonymous source as implicit" do
        Babushka::Base.sources.anonymous.type.should == :implicit
      end
      it "should classify the core source as local" do
        Babushka::Base.sources.core.type.should == :local
      end
      it "should classify the current_dir source as local" do
        Babushka::Base.sources.current_dir.type.should == :local
      end
    end
  end

  def define_in source
    Babushka::Base.sources.load_context :source => source do
      yield
    end
  end

  let(:source1) { Babushka::ImplicitSource.new('source_1') }
  let(:source2) { Babushka::ImplicitSource.new('source_2') }
  let!(:anonymous_meta) { define_in(Babushka::Base.sources.anonymous) { meta 'anonymous_meta' } }
  let!(:core_meta) { define_in(Babushka::Base.sources.core) { meta 'core_meta' } }
  let!(:core_from) { define_in(Babushka::Base.sources.core) { meta 'core_from' } }
  let!(:meta1) { define_in(source1) { meta :meta_1 } }
  let!(:meta2) { define_in(source1) { meta 'meta_2' } }
  let!(:meta3) { define_in(source2) { meta :meta_3 } }
  let!(:meta4) { define_in(source2) { meta 'meta_4' } }
  let!(:from1) { define_in(source1) { meta 'from_test' } }
  let!(:from2) { define_in(source2) { meta 'from_test' } }
  let!(:from2_2) { define_in(source2) { meta 'from_test_2' } }

  before {
    Babushka::Source.stub(:present).and_return [source1, source2]
  }

  describe Babushka::SourcePool, '#source_for' do
    before {
      Babushka::Base.sources.stub(:default).and_return([source1])
      Babushka::Source.stub(:present).and_return([source2])
    }
    it "should find core sources" do
      Babushka::Base.sources.source_for('source_1').should == source1
    end
    it "should find cloned sources" do
      Babushka::Base.sources.source_for('source_2').should == source2
    end
  end

  describe '#find_or_suggest' do
    context "basic" do
      let!(:a_dep) { dep 'find_or_suggest' }
      it "should find the dep" do
        Babushka::Base.sources.find_or_suggest('find_or_suggest').should == a_dep
      end
      it "should yield the dep to the block" do
        Babushka::Base.sources.find_or_suggest('find_or_suggest') {|dep| dep }.should == a_dep
      end
    end
    context "namespaced" do
      let(:source) { Babushka::ImplicitSource.new('namespaced') }
      let!(:a_dep) {
        Babushka::Base.sources.load_context :source => source do
          dep 'find_or_suggest namespaced'
        end
      }
      before {
        Babushka::Prompt.stub(:suggest_value_for).and_return(nil)
        Babushka::Source.stub(:present).and_return([source])
      }
      it "should not find the dep without a namespace" do
        Babushka::Levenshtein.stub(:distance).and_return(20) # For performance.
        Babushka::Base.sources.find_or_suggest('find_or_suggest namespaced').should be_nil
      end
      it "should not find the dep with an incorrect namespace" do
        Babushka::Levenshtein.stub(:distance).and_return(20) # For performance.
        Babushka::GitHelpers.stub(:git) # To avoid cloning.
        Babushka::Base.sources.find_or_suggest('incorrect:find_or_suggest namespaced').should be_nil
      end
      it "should find the dep with the correct namespace" do
        Babushka::Base.sources.find_or_suggest('namespaced:find_or_suggest namespaced').should == a_dep
      end
      it "should yield the dep to the block" do
        Babushka::Base.sources.find_or_suggest('namespaced:find_or_suggest namespaced') {|dep| dep }.should == a_dep
      end
    end
    context "from other deps" do
      let(:source) { Babushka::ImplicitSource.new('namespaced') }
      let!(:a_dep) {
        Babushka::Base.sources.load_context :source => source do
          dep 'find_or_suggest namespaced' do
            requires 'find_or_suggest sub_dep'
          end
        end
      }
      context "without namespacing" do
        let!(:sub_dep) { dep 'find_or_suggest sub_dep' }
        before {
          Babushka::Source.stub(:present).and_return([source])
        }
        it "should find the sub dep" do
          sub_dep.should_receive(:process!)
          a_dep.process
        end
      end
      context "in the same namespace" do
        let!(:sub_dep) {
          Babushka::Base.sources.load_context :source => source do
            dep 'find_or_suggest sub_dep'
          end
        }
        before {
          Babushka::Source.stub(:present).and_return([source])
        }
        it "should find the sub dep" do
          sub_dep.should_receive(:process!)
          a_dep.process
        end
      end
      context "in a different namespace" do
        let(:source2) { Babushka::ImplicitSource.new('another namespaced') }
        let!(:sub_dep) {
          Babushka::Base.sources.load_context :source => source2 do
            dep 'find_or_suggest sub_dep'
          end
        }
        before {
          Babushka::Source.stub(:present).and_return([source, source2])
        }
        it "should not find the sub dep" do
          sub_dep.should_not_receive(:process!)
          a_dep.process
        end
      end
    end
  end

  describe Babushka::Dep, '#dep_for, disregarding sources' do
    let!(:the_dep) { dep 'Base.sources.dep_for tests' }
    it "should work for strings" do
      Babushka::Base.sources.dep_for('Base.sources.dep_for tests').should == the_dep
    end
    it "should work for deps" do
      Babushka::Base.sources.dep_for(the_dep).should == the_dep
    end
    it "should reject other arguments" do
      expect {
        Babushka::Base.sources.dep_for(:symbol_name)
      }.to raise_error(ArgumentError, "The dep spec :symbol_name isn't a String or Dep.")
    end
    it "should not find the dep with namespacing" do
      Babushka::GitHelpers.stub(:git) # To avoid cloning.
      Babushka::Base.sources.dep_for('namespaced:Base.sources.dep_for tests').should be_nil
    end
    context "with namespaced dep defined" do
      let(:source) { Babushka::ImplicitSource.new('namespaced') }
      let!(:namespaced_dep) {
        define_in(source) { dep 'Base.sources.dep_for tests' }
      }
      before {
        Babushka::Source.stub(:present).and_return([source])
      }
      it "should find the dep" do
        Babushka::Base.sources.dep_for('namespaced:Base.sources.dep_for tests').should == namespaced_dep
      end
    end
  end

  describe Babushka::SourcePool, '#dep_for' do
    let!(:dep1) { define_in(source1) { dep 'dep 1' } }
    let!(:dep2) { define_in(source1) { dep 'dep 2' } }
    let!(:dep3) { define_in(source2) { dep 'dep 3' } }
    let!(:dep4) { define_in(source2) { dep 'dep 4' } }
    before {
      Babushka::Base.sources.stub(:default).and_return([source1, source2])
      Babushka::Source.stub(:present).and_return([source1, source2])
    }
    it "should look up the correct deps without namespacing" do
      Babushka::Base.sources.dep_for('dep 1').should == dep1
      Babushka::Base.sources.dep_for('dep 4').should == dep4
    end
    it "should find the dep when the namespace is correct" do
      Babushka::Base.sources.dep_for('source_1:dep 1').should == dep1
      Babushka::Base.sources.dep_for('source_2:dep 4').should == dep4
    end
    it "should not find the dep when the namespace is wrong" do
      Babushka::Base.sources.dep_for('source_1:dep 3').should be_nil
      Babushka::Base.sources.dep_for('source_2:dep 2').should be_nil
    end
  end

  describe Babushka::SourcePool, '#dep_for core' do
    let(:core) { Babushka::ImplicitSource.new('core') }
    let!(:dep1) { define_in(core) { dep 'dep 1' } }
    before {
      Babushka::Base.sources.stub(:default).and_return([core])
    }
    it "should find the correct deps without namespacing" do
      Babushka::Base.sources.dep_for('dep 1').should == dep1
    end
    it "should find the dep when the namespace is correct" do
      Babushka::Base.sources.dep_for('core:dep 1').should == dep1
    end
    it "should not find the dep when the namespace is wrong" do
      Babushka::GitHelpers.stub(:git) # To avoid cloning.
      Babushka::Base.sources.dep_for('non_core:dep 1').should be_nil
    end
  end

  describe Babushka::SourcePool, '#load_context' do
    context "without a template" do
      before {
        Babushka::Dep.should_receive(:new).with('load_context', Babushka::Base.sources.anonymous, [], {}, nil)
      }
      it "should pass the correct options" do
        dep 'load_context'
      end
    end
    context "with a template" do
      let(:source) { Babushka::ImplicitSource.new('load_context') }
      let!(:template) {
        Babushka::Base.sources.load_context :source => source do
          meta 'load_context_template'
        end
      }
      let!(:the_dep) {
        Babushka::Base.sources.load_context :source => source do
          dep 'defining test with template.load_context_template'
        end
      }
      it "should use the template" do
        the_dep.template.should == template
      end
    end
    context "with nesting" do
      it "should maintain the outer context after the inner one returns" do
        Babushka::Base.sources.load_context :source => source1 do
          Babushka::Base.sources.current_load_source.should == source1
          Babushka::Base.sources.load_context :source => source2 do
            Babushka::Base.sources.current_load_source.should == source2
          end
          Babushka::Base.sources.current_load_source.should == source1
        end
      end
    end
  end

  describe Babushka::SourcePool, '#template_for' do

    context "without namespacing" do
      it "should find templates in the anonymous source" do
        Babushka::Base.sources.template_for('anonymous_meta').should == anonymous_meta
      end
      it "should find templates in the core source" do
        Babushka::Base.sources.template_for('core_meta').should == core_meta
      end
      it "should not find templates from non-default sources" do
        Babushka::Base.sources.template_for('meta_1').should be_nil
        Babushka::Base.sources.template_for('meta_3').should be_nil
      end
      context "with :from" do
        it "should find the template in the same source" do
          Babushka::Base.sources.template_for('from_test', :from => source1).should == from1
          Babushka::Base.sources.template_for('from_test', :from => source2).should == from2
        end
        context "when it doesn't exist in the :from source" do
          it "should find the template in the core source" do
            Babushka::Base.sources.template_for('core_from', :from => source1).should == core_from
          end
          it "should not find the template in other sources" do
            Babushka::Base.sources.template_for('from_test_2', :from => source1).should be_nil
            Babushka::Base.sources.template_for('from_test_2', :from => source2).should_not be_nil
          end
        end
      end
    end

    context "with namespacing" do
      it "should find the dep when the namespace is correct" do
        Babushka::Base.sources.template_for('source_1:meta_1').should == meta1
        Babushka::Base.sources.template_for('source_2:meta_4').should == meta4
      end
      it "should not find the dep when the namespace is wrong" do
        Babushka::Base.sources.template_for('source_1:').should be_nil
        Babushka::Base.sources.template_for('source_2:meta 2').should be_nil
      end
    end
  end

  describe "template selection during defining" do
    context "with namespacing" do
      it "should use templates from the named source" do
        dep('template selection 1', :template => 'source_1:meta_1').template.should == meta1
      end
      it "should not find the template with the wrong source prefix, and raise" do
        L{
          dep('template selection 2', :template => 'source_2:meta_1').template
        }.should raise_error(Babushka::TemplateNotFound, "There is no template named 'source_2:meta_1' to define 'template selection 2' against.")
      end
    end
    context "without namespacing" do
      context "with :template option" do
        it "should find a template in the same source" do
          define_in(source1) { dep 'template selection 3', :template => 'meta_1' }.template.should == meta1
        end
        it "should not find a template in the wrong source, and raise" do
          L{
            define_in(source1) { dep 'template selection 4', :template => 'meta_3' }.template
          }.should raise_error(Babushka::TemplateNotFound, "There is no template named 'meta_3' to define 'template selection 4' against.")
        end
      end
      context "with suffixes" do
        it "should find a template in the same source" do
          define_in(source1) { dep 'template selection 3.meta_1' }.template.should == meta1
        end
        it "should find a template in the core source" do
          define_in(source1) { dep 'template selection 3.core_meta' }.template.should == core_meta
        end
        it "should not find a template in the wrong source, and use the base template" do
          define_in(source1) { dep 'template selection 4.meta_3' }.template.should == Babushka::Dep.base_template
        end
      end
    end
  end

  after {
    Babushka::Base.sources.anonymous.templates.clear!
    Babushka::Base.sources.core.templates.clear!
  }
end


describe "template selection during defining from a real source" do
  let(:source) { Babushka::Source.new('spec/deps/good', 'good source').tap(&:load!) }
  before {
    Babushka::Source.stub(:present).and_return([source])
  }
  it "should have loaded deps" do
    source.deps.names.should =~ [
      'test dep 1',
      'test dep 2',
      'option-templated dep',
      'suffix-templated dep.test_template'
    ]
  end
  it "should have loaded templates" do
    source.templates.names.should =~ [
      'test_template',
      'test_meta_1'
    ]
  end
  it "should have defined deps against the correct template" do
    source.find('test dep 1').template.should == Babushka::Dep.base_template
    source.find('test dep 2').template.should == Babushka::Dep.base_template
    source.find('option-templated dep').template.should == source.find_template('test_template')
    source.find('suffix-templated dep.test_template').template.should == source.find_template('test_template')
  end
end

describe "nested source loads" do
  let(:outer_source) { Babushka::Source.new('spec/deps/outer', 'outer source').tap(&:load!) }
  let(:nested_source) { Babushka::Source.new('spec/deps/good', 'nested source') }
  before {
    Babushka::Source.stub(:present).and_return([outer_source, nested_source])
  }
  it "should have loaded outer deps" do
    outer_source.deps.names.should =~ [
      'test dep 1',
      'externally templated',
      'locally templated',
      'locally templated.local_template',
      'separate file',
      'separate file.another_local_template'
    ]
    nested_source.deps.names.should == []
  end
  it "should have loaded outer templates" do
    outer_source.templates.names.should =~ [
      'local_template',
      'another_local_template'
    ]
    nested_source.templates.names.should == []
  end
  context "after defining external deps" do
    before {
      outer_source.find('externally templated').context
    }
    it "should have loaded the nested deps" do
      nested_source.deps.names.should =~ [
        'test dep 1',
        'test dep 2',
        'option-templated dep',
        'suffix-templated dep.test_template'
      ]
    end
    it "should have loaded the nested templates" do
      nested_source.templates.names.should =~ [
        'test_template',
        'test_meta_1'
      ]
    end
  end

  it "should have defined deps against the correct template" do
    outer_source.find('test dep 1').template.should == Babushka::Dep.base_template
    outer_source.find('externally templated').template.should == nested_source.find_template('test_template')
    outer_source.find('locally templated').template.should == outer_source.find_template('local_template')
    outer_source.find('locally templated.local_template').template.should == outer_source.find_template('local_template')
    outer_source.find('separate file').template.should == outer_source.find_template('another_local_template')
    outer_source.find('separate file.another_local_template').template.should == outer_source.find_template('another_local_template')
  end
end
