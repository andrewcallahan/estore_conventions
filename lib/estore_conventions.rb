require 'aggtive_record'
require 'acts-as-taggable-on'
require 'paper_trail'

ActsAsTaggableOn.force_lowercase = true


module EstoreConventions     
  extend ActiveSupport::Concern
  include AggtiveRecord::Aggable



  included do
    class_attribute :t_id_attribute

    self.t_id_attribute = :t_id  # by default
    validates_presence_of self.t_id_attribute
    validates_uniqueness_of self.t_id_attribute

  end


  # instance methods

  module ClassMethods
    def find_or_init_by_t_id(tid)
       where(:t_id => tid).first_or_initialize
    end

    # atts_hash are the attributes to assign to the Record
    # identifier_conditions is what the scope for first_or_initialize is called upon
    #  so that an existing object is updated
    #  full_data_object is passed in to be saved as a blob
    def factory_build_for_store(atts_hash, identifier_conditions = {}, full_data_object={}, &blk)      
      if identifier_conditions.empty?
        record = self.new
      else
        record = self.where(identifier_conditions).first_or_initialize
      end
      record.assign_attributes(atts_hash)

      if block_given?
        yield record, full_data_object
      end

      return record
    end


    def attr_t_id(attname)
      puts "WARNING: Customizing t_id and proper validation is not supported yet"
      raise ArgumentError unless column_names.include?(attname.to_s)
      self.t_id_attribute = attname 
    end

    def add_sorted_value_and_sort(foo, opts={})
      if foo.class == Proc 
        self.all.sort_by do |channel| 
          val = foo.call(channel) 
          channel.instance_eval "def sorted_value; #{val}; end"

          -val            
        end
      elsif foo.class == String || foo.class == Symbol
        order_val = opts[:order] || 'DESC'
        self.order("#{foo} #{order_val}").
              select("#{self.table_name}.*, #{self.table_name}.#{foo} AS sorted_value").
              limit(opts[:limit])
      else  
        raise ArgumentError, "#{foo} needs to be a String, Symbol, or Proc"        
      end
    end







  end ##### ClassMethods



  ############ InstanceMethods

  # Note: redone to use PaperTrail.serializer, as reify makes a database call each time
  # for some reason - Dan

  # returns a Hash, with days as the keys: {'2013-10-12' => 100}
  def archived_attribute(attribute, time_frame = 30.days )
    time_frame = (DateTime.now + 1.day).beginning_of_day - time_frame
    arr = self.versions.updates.map do |v| 
      obj = PaperTrail.serializer.load v.object 

      Hashie::Mash.new(obj)
    end

    arr << self

    # weed out old entries
    arr.delete_if{|x| x.rails_updated_at <= time_frame }

    # transform reify objects into hash of {date => value}
    return arr.reduce({}) do |hsh,val|
      hsh[val.rails_updated_at.strftime('%Y-%m-%d')] = val.send(attribute)
      
      hsh
    end
  end


  # UNTESTED
  # returns a scalar (Float)
  def historical_rate_per_day(attribute, time_frame = 30.days)
    arr = archived_attribute(attribute, time_frame).to_a
    first_day, xval = arr[0]
    last_day, yval = arr[-1]

    day_count = (Time.parse(last_day) - Time.parse(first_day)) / ( 60 * 60 * 24).to_f
    diff = yval - xval

    day_span = day_count - 1

    if day_span > 0
      rate = diff.to_f / day_span
    else
      rate = 0
    end

    return rate
  end


  # def archived_attribute(attribute, time_frame=(30.days))
  #   # normalize time since we are returning today as a whole day
  #   time_frame = (DateTime.now + 1.day).beginning_of_day - time_frame

  #   # transform papertrail objects to reify objects
  #   a = self.versions.map {|v| v.reify }

  #   # get rid of nil first version
  #   a.compact!

  #   # add the current object to the array
  #   a << self

  #   # weed out old entries
  #   a.delete_if {|x| x.rails_updated_at <= time_frame }

  #   # sort hash based on key  
  #   a.sort_by!{|x| x.rails_updated_at }

  #   # transform reify objects into hash of {date => value}
  #   a.reduce({}) do |hsh,val|
  #     hsh[val.rails_updated_at.strftime('%Y-%m-%d')] = val.send(attribute)
  #     hsh
  #   end
  # end

  def timestamp_attributes_for_create
    super << :rails_created_at
  end

  def timestamp_attributes_for_update
    super << :rails_updated_at
  end

end

require_relative 'estore_conventions/builder'