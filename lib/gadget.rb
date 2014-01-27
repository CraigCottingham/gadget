# encoding: utf-8

require 'pg'
require 'tsort'

require 'gadget/version'

module Gadget

  class TsortableHash < Hash
    include ::TSort
    alias tsort_each_node each_key
    def tsort_each_child(node, &block)
      (fetch(node) || []).each(&block)
    end
  end

  def self.tables(conn)
    rs = conn.exec("SELECT c.oid, t.tablename FROM pg_tables t INNER JOIN pg_class c ON c.relname=t.tablename WHERE t.schemaname='public' ORDER BY t.tablename")
    tuples = rs.map { | row | row }
    rs.clear
    tuples
  end

  def self.foreign_keys(conn)
    rs = conn.exec("SELECT conrelid, confrelid FROM pg_constraint WHERE contype='f'")
    tuples = rs.map { | row | row }
    rs.clear
    tuples
  end

  def self.tables_in_dependency_order(dbname)
    conn = PG::Connection.open(:dbname => dbname)
    tables = self.tables(conn).reduce({}) { | h, tuple | h[tuple['oid']] = { :tablename => tuple['tablename'] }; h }
    foreign_keys = self.foreign_keys(conn).reduce({}) do | h, tuple |
      h[tuple['conrelid']] ||= []
      h[tuple['conrelid']] << tuple['confrelid']
      h
    end
    foreign_keys.each { | k, v | tables[k][:refs] = v.map { | oid | tables[oid][:tablename] } }
    tables = tables.inject(TsortableHash.new) { | h, (k, v) | h[v[:tablename]] = v[:refs]; h }
    conn.close
    tables.tsort
  end

end
