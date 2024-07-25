# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2018-2024, by Samuel Williams.

require 'protocol/hpack/context'

RSpec.describe Protocol::HPACK::Context do
	let(:context) {Protocol::HPACK::Context.new(table_size: 2048)}

	it 'should be initialized with empty headers' do
		expect(context.table).to be_empty
	end
	
	context '#dup' do
		it "duplicates mutable table state" do
			context.instance_eval do
				add_to_table(['test1', '1'])
				add_to_table(['test2', '2'])
			end

			dup = context.dup
			expect(dup.table).to eq context.table
			expect(dup.table).not_to be context.table
		end
	end
	
	context '#dereference' do
		it "raises an error if the index is out of bounds" do
			expect do
				context.dereference(1024)
			end.to raise_error(Protocol::HPACK::Error)
		end
	end
	
	context '#decode' do
		it "raises an error if the command is invalid" do
			expect do
				header = [:invalid, 0, 'test']
				context.decode(*header)
			end.to raise_error(Protocol::HPACK::Error)
		end
	end
	
	context 'processing' do
		[
			['no indexing', :no_index],
			['never indexed', :never_indexed],
		].each do |desc, type|
			context "#{desc}" do
				it 'should process indexed header with literal value' do
					original_table = context.table.dup

                                        header = [type, 4, '/path']
					emit = context.decode(*header)
					expect(emit).to eq [':path', '/path']
					expect(context.table).to eq original_table
				end

				it 'should process literal header with literal value' do
					original_table = context.table.dup

                                        header = [type, 'x-custom', 'random']
					emit = context.decode(*header)
					expect(emit).to eq ['x-custom', 'random']
					expect(context.table).to eq original_table
				end
			end
		end

		context 'incremental indexing' do
			it 'should process indexed header with literal value' do
				original_table = context.table.dup

                                header = [:incremental, 4, '/path']
				emit = context.decode(*header)
				expect(emit).to eq [':path', '/path']
				expect(context.table - original_table).to eq [[':path', '/path']]
			end

			it 'should process literal header with literal value' do
				original_table = context.table.dup

                                header = [:incremental, 'x-custom', 'random']
				context.decode(*header)
				expect(context.table - original_table).to eq [['x-custom', 'random']]
			end
		end

		context 'size bounds' do
			it 'should drop headers from end of table' do
				context.instance_eval do
					add_to_table(['test1', '1' * 1024])
					add_to_table(['test2', '2' * 500])
				end

				original_table = context.table.dup
				original_size = original_table.join.bytesize + original_table.size * 32

                                header = [:incremental, 'x-custom', 'a' * (2048 - original_size)]
				context.decode(*header)

				expect(context.table.first[0]).to eq 'x-custom'
				expect(context.table.size).to eq original_table.size # number of entries
			end
		end

		it 'should clear table if entry exceeds table size' do
			context.instance_eval do
				add_to_table(['test1', '1' * 1024])
				add_to_table(['test2', '2' * 500])
			end

			h = [:incremental, 'x-custom', 'a']
                        e = [:incremental, 'large', 'a' * 2048]

			context.decode(*h)
			context.decode(*e)
			expect(context.table).to be_empty
		end

		it 'should shrink table if set smaller size' do
			context.instance_eval do
				add_to_table(['test1', '1' * 1024])
				add_to_table(['test2', '2' * 500])
			end

                        header = [:change_table_size, nil, 1500]
			context.decode(*header)
			expect(context.table.size).to be 1
			expect(context.table.first[0]).to eq 'test2'
		end
	end
end
