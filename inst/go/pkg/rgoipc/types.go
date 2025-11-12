// Package rgoipc provides interfaces and types for R/Go IPC using Arrow and mangos
package rgoipc

import (
	"github.com/apache/arrow/go/v18/arrow"
)

// ArrowType represents supported Arrow type mappings for R types
type ArrowType string

const (
	TypeInt32   ArrowType = "int32"   // R integer
	TypeFloat64 ArrowType = "float64" // R numeric
	TypeString  ArrowType = "string"  // R character
	TypeBool    ArrowType = "bool"    // R logical
	TypeList    ArrowType = "list"    // R list -> Arrow struct
	TypeStruct  ArrowType = "struct"  // R data.frame -> Arrow record batch
)

// TypeSpec describes a type for function arguments or returns
type TypeSpec struct {
	Type       ArrowType
	Nullable   bool
	StructDef  *StructDef  // For struct types
	ListSchema *arrow.Schema // For list types
}

// StructDef defines structure for complex types
type StructDef struct {
	Fields []FieldDef
}

// FieldDef defines a field in a struct
type FieldDef struct {
	Name     string
	Type     TypeSpec
	Metadata map[string]string
}

// ArgSpec describes a function argument
type ArgSpec struct {
	Name     string
	Type     TypeSpec
	Optional bool
	Default  interface{}
}

// FunctionSignature describes a Go function callable from R
type FunctionSignature struct {
	Args       []ArgSpec
	ReturnType TypeSpec
	Vectorized bool // Can process batches
	Metadata   map[string]string
}

// FunctionHandler processes Arrow record batches
// Input: Arrow Record containing function arguments
// Output: Arrow Record containing function results
type FunctionHandler func(input arrow.Record) (arrow.Record, error)

// RegisteredFunction represents a function registered for RPC
type RegisteredFunction struct {
	Name         string
	Handler      FunctionHandler
	InputSchema  *arrow.Schema
	OutputSchema *arrow.Schema
	Signature    FunctionSignature
}
