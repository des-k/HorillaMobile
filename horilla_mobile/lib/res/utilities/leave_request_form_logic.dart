import 'package:flutter/material.dart';

const Map<String, String> leaveBreakdownLabels = {
  'full_day': 'Full Day',
  'second_half': 'Second Half',
  'first_half': 'First Half',
};

String leaveBreakdownLabel(String? key) {
  return leaveBreakdownLabels[key] ?? 'Unknown';
}

class LeaveRequestValidationResult {
  const LeaveRequestValidationResult({
    this.validateEmployee = false,
    this.validateLeaveType = false,
    this.validateStartDate = false,
    this.validateStartDateBreakdown = false,
    this.validateEndDate = false,
    this.validateEndDateBreakdown = false,
    this.validateDescription = false,
  });

  final bool validateEmployee;
  final bool validateLeaveType;
  final bool validateStartDate;
  final bool validateStartDateBreakdown;
  final bool validateEndDate;
  final bool validateEndDateBreakdown;
  final bool validateDescription;

  bool get isValid =>
      !validateEmployee &&
      !validateLeaveType &&
      !validateStartDate &&
      !validateStartDateBreakdown &&
      !validateEndDate &&
      !validateEndDateBreakdown &&
      !validateDescription;
}

LeaveRequestValidationResult validateLeaveRequestCreateForm({
  required String employeeText,
  required String? selectedLeaveId,
  required DateTime? startDate,
  required String? startDateBreakdown,
  required DateTime? endDate,
  required String? endDateBreakdown,
  required String description,
}) {
  if (employeeText.trim().isEmpty) {
    return const LeaveRequestValidationResult(validateEmployee: true);
  }
  if (selectedLeaveId == null || selectedLeaveId.trim().isEmpty) {
    return const LeaveRequestValidationResult(validateLeaveType: true);
  }
  if (startDate == null) {
    return const LeaveRequestValidationResult(validateStartDate: true);
  }
  if (startDateBreakdown == null || startDateBreakdown.trim().isEmpty) {
    return const LeaveRequestValidationResult(validateStartDateBreakdown: true);
  }
  if (endDate == null) {
    return const LeaveRequestValidationResult(validateEndDate: true);
  }
  if (endDateBreakdown == null || endDateBreakdown.trim().isEmpty) {
    return const LeaveRequestValidationResult(validateEndDateBreakdown: true);
  }
  if (description.trim().isEmpty) {
    return const LeaveRequestValidationResult(validateDescription: true);
  }
  return const LeaveRequestValidationResult();
}

class LeaveBreakdownDropdown extends StatelessWidget {
  const LeaveBreakdownDropdown({
    super.key,
    required this.label,
    required this.selectedKey,
    this.hasError = false,
    required this.onChanged,
  });

  final String label;
  final String? selectedKey;
  final bool hasError;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: selectedKey,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: label,
        errorText: hasError ? 'Please select $label' : null,
      ),
      items: leaveBreakdownLabels.entries
          .map(
            (entry) => DropdownMenuItem<String>(
              value: entry.key,
              child: Text(entry.value),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}
