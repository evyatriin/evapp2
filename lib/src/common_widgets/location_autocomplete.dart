import 'package:flutter/material.dart';
import '../features/mapping/places_service.dart';

/// A reusable autocomplete widget for location search
class LocationAutocomplete extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final Function(Map<String, String>)? onSelected;
  final Function(String)? onSubmitted;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool showClearButton;
  final InputDecoration? decoration;
  
  const LocationAutocomplete({
    super.key,
    required this.controller,
    this.hintText = 'Search location...',
    this.onSelected,
    this.onSubmitted,
    this.prefixIcon,
    this.suffixIcon,
    this.showClearButton = true,
    this.decoration,
  });

  @override
  State<LocationAutocomplete> createState() => _LocationAutocompleteState();
}

class _LocationAutocompleteState extends State<LocationAutocomplete> {
  final _placesService = PlacesService();
  
  @override
  Widget build(BuildContext context) {
    return Autocomplete<Map<String, String>>(
      optionsBuilder: (TextEditingValue textEditingValue) async {
        if (textEditingValue.text.length < 3) {
          return const Iterable<Map<String, String>>.empty();
        }
        return await _placesService.getAutocompleteSuggestions(textEditingValue.text);
      },
      displayStringForOption: (Map<String, String> option) => option['description'] ?? '',
      onSelected: (Map<String, String> selection) {
        widget.controller.text = selection['description']!;
        widget.onSelected?.call(selection);
      },
      fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
        // Sync controllers
        if (textEditingController.text != widget.controller.text) {
           textEditingController.text = widget.controller.text;
        }
        
        textEditingController.addListener(() {
          widget.controller.text = textEditingController.text;
        });

        final defaultDecoration = InputDecoration(
          hintText: widget.hintText,
          prefixIcon: widget.prefixIcon ?? const Icon(Icons.search),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          suffixIcon: widget.showClearButton && textEditingController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () {
                  textEditingController.clear();
                  widget.controller.clear();
                },
              )
            : widget.suffixIcon,
        );

        return TextField(
          controller: textEditingController,
          focusNode: focusNode,
          decoration: widget.decoration ?? defaultDecoration,
          onSubmitted: (value) {
            onFieldSubmitted();
            widget.onSubmitted?.call(value);
          },
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width - 32,
                maxHeight: 300,
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (BuildContext context, int index) {
                  final option = options.elementAt(index);
                  return ListTile(
                    title: Text(
                      option['description'] ?? '',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    onTap: () => onSelected(option),
                    leading: Icon(
                      Icons.location_on,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    dense: true,
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
