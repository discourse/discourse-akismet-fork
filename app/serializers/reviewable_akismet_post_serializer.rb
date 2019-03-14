class ReviewableAkismetPostSerializer < ReviewableSerializer
  target_attributes :cooked, :raw
end
