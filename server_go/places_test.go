package main
import (
 "net/http/httptest"
 "testing"
)
func TestPlaceAliases(t *testing.T) {
 for input, want := range map[string]string{" UTN FRC ":"Universidad Tecnológica Nacional", "Universidad de arquitectura":"Facultad Arquitectura", "  Vélez   Sársfield ":"velez sarsfield"} {
  if got:=normalizePlaceQuery(input); got!=want { t.Fatalf("%q: got %q, want %q",input,got,want) }
 }
}
func TestPlaceSearchRejectsShortQuery(t *testing.T) {
 response:=httptest.NewRecorder()
 handlePlaces(response,httptest.NewRequest("GET","/api/places?q=a",nil))
 if response.Code!=400 { t.Fatalf("got %d",response.Code) }
}
