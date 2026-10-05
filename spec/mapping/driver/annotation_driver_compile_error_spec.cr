require "../../spec_helper"

private def assert_mapping_compile_error(message : String, code : String, *, line : Int32 = __LINE__) : Nil
  ASPEC::Methods.assert_compile_time_error message, code, preamble: %(require "sqlite3"\nrequire "../../../src/athena-orm"), postamble: %(AORM::EntityManager.new DB.connect("sqlite3::memory:")), line: line
end

# Mapping errors the annotation driver reports at compile time.
# Options that aren't supported yet are rejected here rather than silently ignored.
struct AnnotationDriverCompileErrorTest < ASPEC::TestCase
  def test_lifecycle_callback_with_too_many_parameters : Nil
    assert_mapping_compile_error "Expected 'Widget#on_persist' to have 0..1 parameters, got '2'.", <<-CR
      @[AORMA::Entity]
      class Widget < AORM::Entity
        @[AORMA::Column]
        @[AORMA::ID]
        property id : Int64? = nil

        @[AORMA::PrePersist]
        def on_persist(a, b) : Nil
        end
      end
      CR
  end

  def test_post_load_callback : Nil
    assert_mapping_compile_error "'Widget#on_load': PostLoad lifecycle callbacks are not supported yet.", <<-CR
      @[AORMA::Entity]
      class Widget < AORM::Entity
        @[AORMA::Column]
        @[AORMA::ID]
        property id : Int64? = nil

        @[AORMA::PostLoad]
        def on_load : Nil
        end
      end
      CR
  end

  def test_generated_column : Nil
    assert_mapping_compile_error "'Widget#total': the 'generated' column option is not supported yet.", <<-CR
      @[AORMA::Entity]
      class Widget < AORM::Entity
        @[AORMA::Column]
        @[AORMA::ID]
        property id : Int64? = nil

        @[AORMA::Column(generated: "ALWAYS")]
        property total : Int32? = nil
      end
      CR
  end

  def test_mapped_superclass : Nil
    assert_mapping_compile_error "'Timestamped': mapped superclasses are not supported yet. Share mapped properties through an included module instead.", <<-CR
      @[AORMA::MappedSuperclass]
      abstract class Timestamped < AORM::Entity
        @[AORMA::Column]
        property created_by : String? = nil
      end

      @[AORMA::Entity]
      class Widget < Timestamped
        @[AORMA::Column]
        @[AORMA::ID]
        property id : Int64? = nil
      end
      CR
  end

  def test_embeddable : Nil
    assert_mapping_compile_error "'Address': embeddables are not supported yet.", <<-CR
      @[AORMA::Embeddable]
      class Address < AORM::Entity
        @[AORMA::Column]
        property street : String? = nil
      end
      CR
  end
end
