{$LINKLIB crypto}

function EC_KEY_new_by_curve_name(Nid: Integer): Pointer; cdecl; external;
procedure EC_KEY_free(Key: Pointer); cdecl; external;
function EC_KEY_generate_key(Key: Pointer): Integer; cdecl; external;
function EC_KEY_check_key(Key: Pointer): Integer; cdecl; external;
function EC_KEY_set_private_key(Key, Value: Pointer): Integer; cdecl; external;
function EC_KEY_set_public_key_affine_coordinates(Key, X, Y: Pointer): Integer; cdecl; external;
function EC_KEY_get0_private_key(Key: Pointer): Pointer; cdecl; external;
function EC_KEY_get0_public_key(Key: Pointer): Pointer; cdecl; external;
function EC_KEY_get0_group(Key: Pointer): Pointer; cdecl; external;
function EC_POINT_get_affine_coordinates(Group, Point, X, Y, Context: Pointer): Integer; cdecl; external;
function BN_new: Pointer; cdecl; external;
function BN_bin2bn(Data: Pointer; Count: Integer; Value: Pointer): Pointer; cdecl; external;
function BN_bn2binpad(Value, Data: Pointer; Count: Integer): Integer; cdecl; external;
procedure BN_clear_free(Value: Pointer); cdecl; external;
function ECDSA_SIG_new: Pointer; cdecl; external;
procedure ECDSA_SIG_free(Sig: Pointer); cdecl; external;
procedure ECDSA_SIG_get0(Sig: Pointer; out R, S: Pointer); cdecl; external;
function ECDSA_SIG_set0(Sig, R, S: Pointer): Integer; cdecl; external;
function ECDSA_do_sign(Hash: Pointer; Count: Integer; Key: Pointer): Pointer; cdecl; external;
function ECDSA_do_verify(Hash: Pointer; Count: Integer; Sig, Key: Pointer): Integer; cdecl; external;
function OBJ_txt2nid(Name: PAnsiChar): Integer; cdecl; external;

procedure RequireSuccess(const Success: Boolean);
begin
  if not Success then
    raise EECDSAError.Create('OpenSSL P-256 operation failed');
end;

constructor TECDSAKey.Create;
begin
  inherited;
end;

destructor TECDSAKey.Destroy;
begin
  DestroyKey;
  inherited;
end;

procedure TECDSAKey.DestroyKey;
begin
  EC_KEY_free(FKeyHandle);
  FKeyHandle := nil;
end;

procedure TECDSAKey.KeyHandleRequired;
begin
  RequireSuccess(FKeyHandle <> nil);
end;

procedure TECDSAKey.GenerateKeyPair;
var
  Key: Pointer;
begin
  Key := EC_KEY_new_by_curve_name(OBJ_txt2nid('prime256v1'));
  RequireSuccess(Key <> nil);
  try
    RequireSuccess(EC_KEY_generate_key(Key) = 1);
    DestroyKey;
    FKeyHandle := Key;
    Key := nil;
  finally
    EC_KEY_free(Key);
  end;
end;

procedure TECDSAKey.ImportKey(const PublicKey: TECDSAPublicKey; PrivateData: Pointer);
var
  Key, X, Y, D: Pointer;
begin
  Key := nil;
  X := nil;
  Y := nil;
  D := nil;
  try
    Key := EC_KEY_new_by_curve_name(OBJ_txt2nid('prime256v1'));
    X := BN_bin2bn(@PublicKey.Public_x, 32, nil);
    Y := BN_bin2bn(@PublicKey.Public_y, 32, nil);
    RequireSuccess((Key <> nil) and (X <> nil) and (Y <> nil));
    RequireSuccess(EC_KEY_set_public_key_affine_coordinates(Key, X, Y) = 1);
    if PrivateData <> nil then begin
      D := BN_bin2bn(PrivateData, 32, nil);
      RequireSuccess(D <> nil);
      RequireSuccess(EC_KEY_set_private_key(Key, D) = 1);
    end;
    RequireSuccess(EC_KEY_check_key(Key) = 1);
    DestroyKey;
    FKeyHandle := Key;
    Key := nil;
  finally
    BN_clear_free(D);
    BN_clear_free(Y);
    BN_clear_free(X);
    EC_KEY_free(Key);
  end;
end;

procedure TECDSAKey.ImportPrivateKey(constref APrivateKey: TECDSAPrivateKey);
begin
  ImportKey(APrivateKey.PublicKey, @APrivateKey.Private_d);
end;

procedure TECDSAKey.ImportPublicKey(constref APublicKey: TECDSAPublicKey);
begin
  ImportKey(APublicKey, nil);
end;

procedure TECDSAKey.ExportPublicKey(out APublicKey: TECDSAPublicKey);
var
  X, Y: Pointer;
begin
  KeyHandleRequired;
  X := BN_new;
  Y := BN_new;
  try
    RequireSuccess((X <> nil) and (Y <> nil));
    RequireSuccess(EC_POINT_get_affine_coordinates(EC_KEY_get0_group(FKeyHandle),
      EC_KEY_get0_public_key(FKeyHandle), X, Y, nil) = 1);
    RequireSuccess(BN_bn2binpad(X, @APublicKey.Public_x, 32) = 32);
    RequireSuccess(BN_bn2binpad(Y, @APublicKey.Public_y, 32) = 32);
  finally
    BN_clear_free(Y);
    BN_clear_free(X);
  end;
end;

procedure TECDSAKey.ExportPrivateKey(out APrivateKey: TECDSAPrivateKey);
var
  D: Pointer;
begin
  APrivateKey.Clear;
  ExportPublicKey(APrivateKey.PublicKey);
  D := EC_KEY_get0_private_key(FKeyHandle);
  RequireSuccess(D <> nil);
  RequireSuccess(BN_bn2binpad(D, @APrivateKey.Private_d, 32) = 32);
end;

procedure TECDSAKey.SignHash(const AHash: array of Byte; out ASignature: TECDSASignature);
var
  Sig, R, S: Pointer;
begin
  ASignature.Clear;
  KeyHandleRequired;
  RequireSuccess((Length(AHash) > 0) and (Length(AHash) <= High(Integer)));
  Sig := ECDSA_do_sign(@AHash[0], Length(AHash), FKeyHandle);
  RequireSuccess(Sig <> nil);
  try
    ECDSA_SIG_get0(Sig, R, S);
    RequireSuccess(BN_bn2binpad(R, @ASignature.Sig_r, 32) = 32);
    RequireSuccess(BN_bn2binpad(S, @ASignature.Sig_s, 32) = 32);
  finally
    ECDSA_SIG_free(Sig);
  end;
end;

function TECDSAKey.VerifySignature(const AHash: array of Byte;
  const ASignature: TECDSASignature): Boolean;
var
  Sig, R, S: Pointer;
  Status: Integer;
begin
  KeyHandleRequired;
  RequireSuccess((Length(AHash) > 0) and (Length(AHash) <= High(Integer)));
  Sig := nil;
  R := nil;
  S := nil;
  try
    Sig := ECDSA_SIG_new;
    R := BN_bin2bn(@ASignature.Sig_r, 32, nil);
    S := BN_bin2bn(@ASignature.Sig_s, 32, nil);
    RequireSuccess((Sig <> nil) and (R <> nil) and (S <> nil));
    RequireSuccess(ECDSA_SIG_set0(Sig, R, S) = 1);
    R := nil;
    S := nil;
    Status := ECDSA_do_verify(@AHash[0], Length(AHash), Sig, FKeyHandle);
    RequireSuccess(Status >= 0);
    Result := Status = 1;
  finally
    BN_clear_free(S);
    BN_clear_free(R);
    ECDSA_SIG_free(Sig);
  end;
end;
