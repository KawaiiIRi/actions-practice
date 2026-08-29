package main

import "testing"

func TestEvenOrOdd(t *testing.T) {
	result := EvenOrOdd(10)
	if result != "even" {
		t.Errorf("expected: even, actual: %s", result)
	}
}
func TestEvenOrOddWithOddNumber(t *testing.T) {
	result := EvenOrOdd(9)
	if result != "odd" {
		t.Errorf("expected: odd, actual: %s", result)
	}
}
